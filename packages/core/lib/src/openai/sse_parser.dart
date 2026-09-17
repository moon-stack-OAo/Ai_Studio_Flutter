import 'dart:convert';

import '../chat/chat_errors.dart';
import '../chat/chat_models.dart';

/// 单条 SSE `data:` 解析结果（content 与/或 tool_calls 增量）。
class SseDeltaEvent {
  const SseDeltaEvent({
    this.delta = '',
    this.done = false,
    this.toolCallDeltas = const [],
    this.finishReason,
  });

  /// 增量文本（可能为空）。
  final String delta;

  /// 是否收到 `[DONE]`。
  final bool done;

  /// 本帧 `delta.tool_calls` 增量（按 index；可能为空）。
  final List<SseToolCallDelta> toolCallDeltas;

  /// `choices[0].finish_reason`（如 `stop` / `tool_calls`）；多数帧为空。
  final String? finishReason;

  bool get hasToolCallDeltas => toolCallDeltas.isNotEmpty;
}

/// 单帧内某一 index 的 tool_call 增量（OpenAI streaming 形态）。
class SseToolCallDelta {
  const SseToolCallDelta({
    required this.index,
    this.id,
    this.type,
    this.name,
    this.argumentsDelta,
  });

  final int index;
  final String? id;
  final String? type;

  /// function.name 增量（通常首帧完整给出）。
  final String? name;

  /// function.arguments 增量字符串。
  final String? argumentsDelta;
}

/// 从一行 SSE 文本提取 payload（仅认 `data:`）；非 data 行返回 null。
String? extractSseDataPayload(String line) {
  final trimmed = line.trim();
  if (!trimmed.startsWith('data:')) return null;
  return trimmed.substring(5).trim();
}

List<SseToolCallDelta> _parseToolCallDeltas(Object? raw) {
  if (raw is! List || raw.isEmpty) return const [];
  final out = <SseToolCallDelta>[];
  for (final e in raw) {
    if (e is! Map) continue;
    final indexRaw = e['index'];
    final index = indexRaw is num
        ? indexRaw.toInt()
        : int.tryParse(indexRaw?.toString() ?? '') ?? out.length;
    String? id = e['id']?.toString();
    if (id != null && id.isEmpty) id = null;
    String? type = e['type']?.toString();
    if (type != null && type.isEmpty) type = null;
    String? name;
    String? argsDelta;
    final fn = e['function'];
    if (fn is Map) {
      final n = fn['name']?.toString();
      if (n != null && n.isNotEmpty) name = n;
      if (fn['arguments'] != null) {
        argsDelta = fn['arguments'].toString();
      }
    }
    out.add(
      SseToolCallDelta(
        index: index,
        id: id,
        type: type,
        name: name,
        argumentsDelta: argsDelta,
      ),
    );
  }
  return out;
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
  var toolDeltas = const <SseToolCallDelta>[];
  final deltaObj = choice['delta'];
  if (deltaObj is Map) {
    if (deltaObj['content'] != null) {
      delta = deltaObj['content'].toString();
    }
    toolDeltas = _parseToolCallDeltas(deltaObj['tool_calls']);
  } else {
    final message = choice['message'];
    if (message is Map) {
      if (message['content'] != null) {
        delta = message['content'].toString();
      }
      toolDeltas = _parseToolCallDeltas(message['tool_calls']);
    } else if (choice['text'] is String) {
      delta = choice['text'] as String;
    }
  }

  final finishRaw = choice['finish_reason']?.toString();
  final finishReason =
      (finishRaw == null || finishRaw.isEmpty || finishRaw == 'null')
          ? null
          : finishRaw;

  return SseDeltaEvent(
    delta: delta,
    toolCallDeltas: toolDeltas,
    finishReason: finishReason,
  );
}

/// 将流式 tool_call 增量按 index 合并为完整 [ChatToolCall] 列表。
class ToolCallAccumulator {
  final Map<int, _AccSlot> _slots = {};

  void apply(Iterable<SseToolCallDelta> deltas) {
    for (final d in deltas) {
      final slot = _slots.putIfAbsent(d.index, _AccSlot.new);
      if (d.id != null && d.id!.isNotEmpty) slot.id = d.id!;
      if (d.type != null && d.type!.isNotEmpty) slot.type = d.type!;
      if (d.name != null && d.name!.isNotEmpty) {
        slot.name = '${slot.name}${d.name}';
      }
      if (d.argumentsDelta != null && d.argumentsDelta!.isNotEmpty) {
        slot.arguments.write(d.argumentsDelta);
      }
    }
  }

  /// 按 index 升序产出；缺 id/name 的槽仍保留（调用方决定是否过滤）。
  List<ChatToolCall> snapshot() {
    final keys = _slots.keys.toList()..sort();
    return [
      for (final k in keys)
        ChatToolCall(
          id: _slots[k]!.id,
          type: _slots[k]!.type,
          name: _slots[k]!.name,
          arguments: _slots[k]!.arguments.toString(),
        ),
    ];
  }

  bool get isEmpty => _slots.isEmpty;

  void reset() => _slots.clear();
}

class _AccSlot {
  String id = '';
  String type = 'function';
  String name = '';
  final StringBuffer arguments = StringBuffer();
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
