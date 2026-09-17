import 'chat_models.dart';

const int defaultChatContextMaxTurns = 20;
const int defaultChatContextMaxChars = 32000;
const double chatContextWarnRatio = 0.8;

/// 以 user 消息条数为轮数。
int countChatTurns(Iterable<ChatMessage> messages) {
  var n = 0;
  for (final m in messages) {
    if (m.role == ChatRole.user) n++;
  }
  return n;
}

/// 粗估字符数（非 Token）；含 tool_calls 参数与 toolCallId。
int estimateChatChars(Iterable<ChatMessage> messages) {
  var total = 0;
  for (final m in messages) {
    total += m.content.length;
    if (m.toolCallId != null) total += m.toolCallId!.length;
    for (final tc in m.toolCalls) {
      total += tc.id.length + tc.name.length + tc.arguments.length;
    }
  }
  return total;
}

/// 丢弃最旧一轮：从首个 user 起，直到下一 user（不含）。
///
/// 一轮内可含 assistant（含 tool_calls）与随后的 role=tool 结果；
/// 整轮一起丢，避免留下不成对的 tool 消息。
List<ChatMessage> _dropOldestTurn(List<ChatMessage> rest) {
  final firstUser = rest.indexWhere((m) => m.role == ChatRole.user);
  if (firstUser < 0) return rest;
  var nextUser = -1;
  for (var i = firstUser + 1; i < rest.length; i++) {
    if (rest[i].role == ChatRole.user) {
      nextUser = i;
      break;
    }
  }
  if (nextUser < 0) return rest;
  return rest.sublist(nextUser);
}

/// 裁剪起点前若落在 tool 结果上，回退到对应 assistant（含 tool_calls），
/// 保证发出的历史不出现「孤立 tool」。
int _alignTrimStart(List<ChatMessage> rest, int startIdx) {
  if (startIdx <= 0 || startIdx >= rest.length) return startIdx;
  var i = startIdx;
  while (i > 0 && rest[i].role == ChatRole.tool) {
    i--;
  }
  // 若当前是紧跟 tool 的 assistant（带 tool_calls），保留它；
  // 若前面还有更早的 tool，继续回退由 while 处理。
  if (i > 0 &&
      rest[i].role == ChatRole.assistant &&
      rest[i].hasToolCalls) {
    // 已对齐到发起 tool_calls 的 assistant。
    return i;
  }
  if (rest[i].role == ChatRole.tool) {
    // 仍孤立：再向前找带 tool_calls 的 assistant。
    for (var j = i; j >= 0; j--) {
      if (rest[j].role == ChatRole.assistant && rest[j].hasToolCalls) {
        return j;
      }
      if (rest[j].role == ChatRole.user) break;
    }
  }
  return i;
}

/// 裁剪结果。
class TrimChatResult {
  const TrimChatResult({
    required this.messages,
    required this.truncated,
    required this.truncatedByChars,
    required this.droppedTurns,
    required this.totalTurns,
    required this.keptTurns,
    required this.maxTurns,
    required this.nearLimit,
    required this.totalChars,
    required this.keptChars,
    required this.maxChars,
    required this.nearCharLimit,
  });

  final List<ChatMessage> messages;
  final bool truncated;
  final bool truncatedByChars;
  final int droppedTurns;
  final int totalTurns;
  final int keptTurns;
  final int maxTurns;
  final bool nearLimit;
  final int totalChars;
  final int keptChars;
  final int maxChars;
  final bool nearCharLimit;
}

/// 保留全部 system + 最近 [maxTurns] 轮；可选字符预算。
///
/// tool 轨迹随所属 user 轮一起保留/丢弃；起点对齐避免不成对 tool。
TrimChatResult trimChatMessages(
  List<ChatMessage> messages, {
  bool enabled = true,
  int maxTurns = defaultChatContextMaxTurns,
  bool maxCharsEnabled = false,
  int maxChars = defaultChatContextMaxChars,
}) {
  final turnsLimit = maxTurns < 1 ? 1 : maxTurns;
  final charsLimit = maxChars < 1 ? 1 : maxChars;

  final system = <ChatMessage>[];
  final rest = <ChatMessage>[];
  for (final m in messages) {
    if (m.role == ChatRole.system) {
      system.add(m);
    } else if (m.role == ChatRole.user ||
        m.role == ChatRole.assistant ||
        m.role == ChatRole.tool) {
      rest.add(m);
    }
  }

  final totalTurns = countChatTurns(rest);
  var kept = rest;
  var truncated = false;
  var droppedTurns = 0;

  if (enabled && totalTurns > turnsLimit) {
    var usersSeen = 0;
    var startIdx = 0;
    for (var i = rest.length - 1; i >= 0; i--) {
      if (rest[i].role == ChatRole.user) {
        usersSeen++;
        if (usersSeen >= turnsLimit) {
          startIdx = i;
          break;
        }
      }
    }
    startIdx = _alignTrimStart(rest, startIdx);
    kept = rest.sublist(startIdx);
    truncated = true;
    droppedTurns = totalTurns - countChatTurns(kept);
  }

  var resultMessages = [...system, ...kept];
  final totalChars = estimateChatChars(resultMessages);
  var truncatedByChars = false;

  if (maxCharsEnabled && totalChars > charsLimit) {
    var working = kept;
    while (estimateChatChars([...system, ...working]) > charsLimit) {
      final next = _dropOldestTurn(working);
      if (identical(next, working) || next.length == working.length) break;
      working = next;
      truncatedByChars = true;
    }
    if (truncatedByChars) {
      droppedTurns = totalTurns - countChatTurns(working);
      truncated = true;
      kept = working;
      resultMessages = [...system, ...kept];
    }
  }

  final keptTurns = countChatTurns(kept);
  final keptChars = estimateChatChars(resultMessages);
  final nearLimit =
      enabled && totalTurns >= (turnsLimit * chatContextWarnRatio).ceil();
  final nearCharLimit = maxCharsEnabled &&
      keptChars >= (charsLimit * chatContextWarnRatio).ceil();

  return TrimChatResult(
    messages: resultMessages,
    truncated: truncated,
    truncatedByChars: truncatedByChars,
    droppedTurns: droppedTurns,
    totalTurns: totalTurns,
    keptTurns: keptTurns,
    maxTurns: turnsLimit,
    nearLimit: nearLimit,
    totalChars: totalChars,
    keptChars: keptChars,
    maxChars: charsLimit,
    nearCharLimit: nearCharLimit,
  );
}

/// 组装 API messages：system 前置；history 含 user / assistant / tool。
///
/// assistant 若有 [ChatMessage.toolCalls] 则写入 OpenAI `tool_calls`；
/// role=tool 写入 `tool_call_id`。
///
/// [attachmentDataUrls]：`messageId → data:` URL 列表；有附图的 user 消息
/// 使用 parts（text + image_url）；无附图仍用 string content。
List<Map<String, dynamic>> buildApiMessages({
  required List<ChatMessage> history,
  String? systemPrompt,
  Map<String, List<String>>? attachmentDataUrls,
}) {
  final out = <Map<String, dynamic>>[];
  final prompt = systemPrompt?.trim();
  if (prompt != null && prompt.isNotEmpty) {
    out.add({'role': 'system', 'content': prompt});
  }
  final urlsByMsg = attachmentDataUrls ?? const <String, List<String>>{};
  for (final m in history) {
    if (m.role == ChatRole.system) continue;

    if (m.role == ChatRole.tool) {
      final map = <String, dynamic>{
        'role': 'tool',
        'content': m.content,
      };
      final tcid = m.toolCallId;
      if (tcid != null && tcid.isNotEmpty) {
        map['tool_call_id'] = tcid;
      }
      out.add(map);
      continue;
    }

    if (m.role != ChatRole.user && m.role != ChatRole.assistant) continue;

    final urls = urlsByMsg[m.id];
    Map<String, dynamic> entry;
    if (m.role == ChatRole.user && urls != null && urls.isNotEmpty) {
      final parts = <Map<String, dynamic>>[];
      final text = m.content;
      if (text.isNotEmpty) {
        parts.add({'type': 'text', 'text': text});
      }
      for (final url in urls) {
        if (url.isEmpty) continue;
        parts.add({
          'type': 'image_url',
          'image_url': {'url': url},
        });
      }
      if (parts.isEmpty) {
        entry = {'role': m.role.wire, 'content': ''};
      } else {
        entry = {'role': m.role.wire, 'content': parts};
      }
    } else {
      entry = {'role': m.role.wire, 'content': m.content};
    }

    if (m.role == ChatRole.assistant && m.hasToolCalls) {
      entry['tool_calls'] = m.toolCalls.map((t) => t.toApiJson()).toList();
    }
    out.add(entry);
  }
  return out;
}
