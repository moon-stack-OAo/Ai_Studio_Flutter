import '../mcp/mcp_models.dart';
import '../mcp/mcp_sanitize.dart';
import 'chat_models.dart';

/// 对话列表展示单元：普通消息，或一轮工具调用聚合。
sealed class ChatDisplayItem {
  const ChatDisplayItem();
}

/// 普通气泡（用户 / 助手正文 / 非工具系统消息）。
class ChatDisplayMessage extends ChatDisplayItem {
  const ChatDisplayMessage(this.message, {this.hideToolCallsStrip = false});

  final ChatMessage message;

  /// 为 true 时助手气泡不单独渲染「调用了工具」条（已由聚合卡承接）。
  final bool hideToolCallsStrip;
}

/// 一轮 tool_calls + 对应 role=tool 结果，收成一条折叠卡。
class ChatDisplayToolRound extends ChatDisplayItem {
  const ChatDisplayToolRound({required this.traces, this.anchorMessageId});

  final List<ChatToolCallTrace> traces;

  /// 触发本轮的 assistant 消息 id（若有）。
  final String? anchorMessageId;

  /// UI 折叠状态键；首个调用不变时，live 更新、追加调用或落盘不会改变它。
  /// 由调用方再以 sessionId 命名空间隔离；无调用 id 时退回历史锚点。
  String get groupId {
    final firstId = traces.isEmpty ? '' : traces.first.toolCallId.trim();
    return firstId.isNotEmpty
        ? 'tool-group:call:$firstId'
        : 'tool-group:message:${anchorMessageId ?? ''}';
  }
}

/// 纯展示投影，不修改消息、live 轨迹、执行或授权状态。
///
/// 非空 toolCallId 全局去重：live 的最后一次更新覆盖历史原位置，
/// 未关联历史的 live 按首次出现顺序附尾。无 id 的项不能可靠关联，不去重。
/// 只合并相邻工具项；任何普通消息（包括 assistant 正文）都是硬边界。
/// UI 应仅渲染此返回值，不能再另外追加 live 卡片。
List<ChatDisplayItem> groupChatMessagesForDisplay(
  List<ChatMessage> messages, {
  List<ChatToolCallTrace> liveTraces = const [],
}) {
  final liveById = <String, ChatToolCallTrace>{};
  for (final trace in liveTraces) {
    final id = trace.toolCallId.trim();
    if (id.isNotEmpty) liveById[id] = trace;
  }
  final seen = <String>{};
  final out = <ChatDisplayItem>[];

  void appendRound(List<ChatToolCallTrace> traces, String? anchor) {
    if (traces.isEmpty) return;
    final previous = out.isEmpty ? null : out.last;
    if (previous is ChatDisplayToolRound) {
      out[out.length - 1] = ChatDisplayToolRound(
        traces: List.unmodifiable([...previous.traces, ...traces]),
        anchorMessageId: previous.anchorMessageId,
      );
    } else {
      out.add(
        ChatDisplayToolRound(
          traces: List.unmodifiable(traces),
          anchorMessageId: anchor,
        ),
      );
    }
  }

  for (final item in _groupHistory(messages)) {
    if (item is ChatDisplayMessage) {
      out.add(item);
      continue;
    }
    final round = item as ChatDisplayToolRound;
    final traces = <ChatToolCallTrace>[];
    for (final trace in round.traces) {
      final id = trace.toolCallId.trim();
      if (id.isNotEmpty && !seen.add(id)) continue;
      traces.add(liveById[id] ?? trace);
    }
    appendRound(traces, round.anchorMessageId);
  }

  final trailing = <ChatToolCallTrace>[];
  for (final trace in liveTraces) {
    final id = trace.toolCallId.trim();
    if (id.isNotEmpty && !seen.add(id)) continue;
    trailing.add(liveById[id] ?? trace);
  }
  appendRound(trailing, null);
  return List.unmodifiable(out);
}

List<ChatDisplayItem> _groupHistory(List<ChatMessage> messages) {
  final resultsById = <String, ChatMessage>{};
  for (final message in messages) {
    final id = message.toolCallId?.trim() ?? '';
    if (message.role == ChatRole.tool && id.isNotEmpty) {
      resultsById[id] = message;
    }
  }
  final out = <ChatDisplayItem>[];
  var i = 0;
  while (i < messages.length) {
    final m = messages[i];

    if (m.role == ChatRole.assistant && m.hasToolCalls) {
      final tools = <ChatMessage>[];
      var j = i + 1;
      while (j < messages.length && messages[j].role == ChatRole.tool) {
        tools.add(messages[j]);
        j++;
      }
      final traces = buildToolRoundTraces(
        toolCalls: m.toolCalls,
        toolResults: [
          ...tools,
          // 延迟落盘的结果也回填调用原位置，不挪动或跨越正文分组。
          for (final call in m.toolCalls) ?resultsById[call.id.trim()],
        ],
      );
      // 工具调用已由聚合卡承接；streaming 本身不是助手正文。
      final hasBody = _hasAssistantDisplayBody(m);
      if (hasBody) {
        out.add(ChatDisplayMessage(m, hideToolCallsStrip: true));
      }
      if (traces.isNotEmpty) {
        out.add(ChatDisplayToolRound(traces: traces, anchorMessageId: m.id));
      }
      i = j;
      continue;
    }

    if (m.role == ChatRole.tool) {
      final tools = <ChatMessage>[];
      while (i < messages.length && messages[i].role == ChatRole.tool) {
        tools.add(messages[i]);
        i++;
      }
      final traces = buildToolRoundTraces(
        toolCalls: const [],
        toolResults: tools,
      );
      if (traces.isNotEmpty) {
        out.add(ChatDisplayToolRound(traces: traces));
      }
      continue;
    }

    // facade 在工具结果后先追加空 streaming 助手，再请求下一轮。
    // 它只是工具链的等待占位，不应制造气泡或切断相邻工具分组。
    // 初次请求（前项不是工具）、正文/附件、失败及停止仍保留。
    final isToolChainWait =
        m.role == ChatRole.assistant &&
        m.streaming &&
        !_hasAssistantDisplayBody(m) &&
        out.isNotEmpty &&
        out.last is ChatDisplayToolRound;
    if (!isToolChainWait) out.add(ChatDisplayMessage(m));
    i++;
  }
  return out;
}

bool _hasAssistantDisplayBody(ChatMessage message) =>
    message.content.trim().isNotEmpty ||
    message.attachments.isNotEmpty ||
    message.error ||
    message.stopped;

/// 由 assistant.toolCalls 与后续 tool 结果消息拼出轨迹摘要。
List<ChatToolCallTrace> buildToolRoundTraces({
  required List<ChatToolCall> toolCalls,
  required List<ChatMessage> toolResults,
}) {
  final byId = <String, ChatMessage>{};
  for (final t in toolResults) {
    final id = t.toolCallId?.trim();
    if (id != null && id.isNotEmpty) {
      byId[id] = t;
    }
  }

  final traces = <ChatToolCallTrace>[];
  final seen = <String>{};

  for (final call in toolCalls) {
    final id = call.id.trim().isEmpty ? call.name : call.id.trim();
    seen.add(id);
    final result = byId[call.id] ?? byId[id];
    traces.add(_traceFromCallAndResult(call: call, result: result));
  }

  // 无匹配 call 的孤儿 tool 结果仍展示。
  for (final t in toolResults) {
    final id = t.toolCallId?.trim() ?? '';
    if (id.isNotEmpty && seen.contains(id)) continue;
    if (id.isEmpty && toolCalls.isNotEmpty) {
      // 无 id 时若已有 call 覆盖，跳过避免重复。
      continue;
    }
    traces.add(_traceFromOrphanResult(t));
    if (id.isNotEmpty) seen.add(id);
  }

  return traces;
}

ChatToolCallTrace _traceFromCallAndResult({
  required ChatToolCall call,
  ChatMessage? result,
}) {
  final args = mcpSanitizeSummary(call.arguments, maxLen: 120);
  if (result == null) {
    return ChatToolCallTrace(
      toolCallId: call.id,
      serverId: '',
      serverDisplayName: '',
      toolName: call.name,
      // 历史缺失并不能证明执行成功；live 投影会用真实状态覆盖。
      status: McpToolCallStatus.queued,
      argumentsSummary: args.isEmpty ? null : args,
      resultSummary: '历史记录缺少工具结果',
    );
  }
  return _traceFromOrphanResult(
    result,
    toolName: call.name,
    toolCallId: call.id,
    argumentsSummary: args.isEmpty ? null : args,
  );
}

ChatToolCallTrace _traceFromOrphanResult(
  ChatMessage result, {
  String? toolName,
  String? toolCallId,
  String? argumentsSummary,
}) {
  final id = (toolCallId ?? result.toolCallId)?.trim() ?? result.id;
  final name = (toolName != null && toolName.isNotEmpty) ? toolName : '工具';
  final body = result.content.trim();
  final summary = mcpSanitizeSummary(body, maxLen: 200);
  // 新记录以显式元数据为准；旧记录仅信任结构化 error/stopped，
  // 不把成功内容里的“用户拒绝”等字样误判成状态。
  final status =
      result.toolResultStatus ??
      (result.error
          ? McpToolCallStatus.failed
          : result.stopped
          ? McpToolCallStatus.cancelled
          : McpToolCallStatus.success);
  return ChatToolCallTrace(
    toolCallId: id,
    serverId: '',
    serverDisplayName: '',
    toolName: name,
    status: status,
    argumentsSummary: argumentsSummary,
    resultSummary: summary.isEmpty ? null : summary,
    errorMessage: status == McpToolCallStatus.failed
        ? mcpSanitizeSummary(result.errorMessage ?? summary, maxLen: 200)
        : null,
  );
}
