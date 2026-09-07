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

/// 粗估字符数（非 Token）。
int estimateChatChars(Iterable<ChatMessage> messages) {
  var total = 0;
  for (final m in messages) {
    total += m.content.length;
  }
  return total;
}

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
    } else if (m.role == ChatRole.user || m.role == ChatRole.assistant) {
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

/// 组装 API messages：system 前置，history 仅 user/assistant。
List<Map<String, String>> buildApiMessages({
  required List<ChatMessage> history,
  String? systemPrompt,
}) {
  final out = <Map<String, String>>[];
  final prompt = systemPrompt?.trim();
  if (prompt != null && prompt.isNotEmpty) {
    out.add({'role': 'system', 'content': prompt});
  }
  for (final m in history) {
    if (m.role == ChatRole.user || m.role == ChatRole.assistant) {
      out.add({'role': m.role.wire, 'content': m.content});
    }
  }
  return out;
}
