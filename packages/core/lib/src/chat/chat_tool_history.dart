import '../mcp/mcp_models.dart';
import '../mcp/mcp_sanitize.dart';
import 'chat_models.dart';

/// 对话列表展示单元：普通消息，或一轮工具调用聚合。
sealed class ChatDisplayItem {
  const ChatDisplayItem();
}

/// 普通气泡（用户 / 助手正文 / 非工具系统消息）。
class ChatDisplayMessage extends ChatDisplayItem {
  const ChatDisplayMessage(
    this.message, {
    this.hideToolCallsStrip = false,
  });

  final ChatMessage message;

  /// 为 true 时助手气泡不单独渲染「调用了工具」条（已由聚合卡承接）。
  final bool hideToolCallsStrip;
}

/// 一轮 tool_calls + 对应 role=tool 结果，收成一条折叠卡。
class ChatDisplayToolRound extends ChatDisplayItem {
  const ChatDisplayToolRound({
    required this.traces,
    this.anchorMessageId,
  });

  final List<ChatToolCallTrace> traces;

  /// 触发本轮的 assistant 消息 id（若有）。
  final String? anchorMessageId;
}

/// 将会话消息折叠为展示列表：相邻「assistant.toolCalls + tool 结果」合成一轮。
List<ChatDisplayItem> groupChatMessagesForDisplay(List<ChatMessage> messages) {
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
        toolResults: tools,
      );
      final hasBody = m.content.trim().isNotEmpty ||
          m.error ||
          m.streaming ||
          m.stopped;
      if (hasBody) {
        out.add(ChatDisplayMessage(m, hideToolCallsStrip: true));
      }
      if (traces.isNotEmpty) {
        out.add(ChatDisplayToolRound(
          traces: traces,
          anchorMessageId: m.id,
        ));
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

    out.add(ChatDisplayMessage(m));
    i++;
  }
  return out;
}

/// 由 assistant.toolCalls 与后续 tool 结果消息拼出轨迹摘要。
List<ChatToolCallTrace> buildToolRoundTraces({
  required List<ChatToolCall> toolCalls,
  required List<ChatMessage> toolResults,
}) {
  final byId = <String, ChatMessage>{};
  for (final t in toolResults) {
    final id = t.toolCallId?.trim();
    if (id != null && id.isNotEmpty) {
      byId.putIfAbsent(id, () => t);
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
      status: McpToolCallStatus.success,
      argumentsSummary: args.isEmpty ? null : args,
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
  final name = (toolName != null && toolName.isNotEmpty)
      ? toolName
      : (result.toolCallId?.isNotEmpty == true
          ? '工具'
          : '工具');
  final body = result.content.trim();
  final summary = mcpSanitizeSummary(body, maxLen: 200);
  final status = result.error
      ? McpToolCallStatus.failed
      : (body.contains('用户拒绝') || body.contains('策略拒绝')
          ? McpToolCallStatus.rejected
          : McpToolCallStatus.success);
  return ChatToolCallTrace(
    toolCallId: id,
    serverId: '',
    serverDisplayName: '',
    toolName: name,
    status: status,
    argumentsSummary: argumentsSummary,
    resultSummary: summary.isEmpty ? null : summary,
    errorMessage: result.error ? (result.errorMessage ?? summary) : null,
  );
}
