import 'dart:convert';

import '../chat/chat_errors.dart';

/// 单条 SSE `data:` 解析结果。
class SseDeltaEvent {
  const SseDeltaEvent({this.delta = '', this.done = false});

  /// 增量文本（可能为空）。
  final String delta;

  /// 是否收到 `[DONE]`。
  final bool done;
}

/// 从一行 SSE 文本提取 payload（仅认 `data:`）；非 data 行返回 null。
String? extractSseDataPayload(String line) {
  final trimmed = line.trim();
  if (!trimmed.startsWith('data:')) return null;
  return trimmed.substring(5).trim();
}

/// 解析单条 data payload。
/// - `[DONE]` → done
/// - 不完整 JSON → 返回 null（吞掉）
/// - 含 error 且无 choices → 抛 [ChatApiException]
SseDeltaEvent? parseSseDataPayload(String payload) {
  if (payload.isEmpty || payload == '[DONE]') {
    return const SseDeltaEvent(done: true);
  }
  Object? json;
  try {
    json = jsonDecode(payload);
  } catch (_) {
    return null;
  }
  if (json is! Map) return null;

  final streamErr = extractApiErrorMessage(json);
  final hasChoices = json['choices'] is List && (json['choices'] as List).isNotEmpty;
  if (streamErr.isNotEmpty &&
      (json.containsKey('error') || json.containsKey('code') || !hasChoices)) {
    final msg = sanitizeErrorText(streamErr, '');
    throw ChatApiException(msg.isNotEmpty ? msg : '流式响应错误');
  }

  final choices = json['choices'];
  if (choices is! List || choices.isEmpty) {
    return const SseDeltaEvent();
  }
  final choice = choices[0];
  if (choice is! Map) return const SseDeltaEvent();

  String delta = '';
  final deltaObj = choice['delta'];
  if (deltaObj is Map && deltaObj['content'] != null) {
    delta = deltaObj['content'].toString();
  } else {
    final message = choice['message'];
    if (message is Map && message['content'] != null) {
      delta = message['content'].toString();
    } else if (choice['text'] is String) {
      delta = choice['text'] as String;
    }
  }
  return SseDeltaEvent(delta: delta);
}

/// 按行缓冲的 SSE 解析器：喂入任意分片文本，产出 delta 事件。
class SseLineParser {
  final StringBuffer _buffer = StringBuffer();

  /// 喂入一段原始文本，返回本段解析出的事件（不含未完成行）。
  List<SseDeltaEvent> addChunk(String chunk) {
    _buffer.write(chunk);
    final text = _buffer.toString();
    final lines = text.split('\n');
    _buffer
      ..clear()
      ..write(lines.isNotEmpty ? lines.removeLast() : '');

    final events = <SseDeltaEvent>[];
    for (final line in lines) {
      final payload = extractSseDataPayload(line);
      if (payload == null) continue;
      final event = parseSseDataPayload(payload);
      if (event != null) events.add(event);
    }
    return events;
  }

  /// 流结束时 flush 残留行。
  List<SseDeltaEvent> flush() {
    final rest = _buffer.toString();
    _buffer.clear();
    if (rest.trim().isEmpty) return const [];
    final events = <SseDeltaEvent>[];
    for (final line in rest.split('\n')) {
      final payload = extractSseDataPayload(line);
      if (payload == null) continue;
      final event = parseSseDataPayload(payload);
      if (event != null) events.add(event);
    }
    return events;
  }

  void reset() => _buffer.clear();
}
