import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseSseDataPayload', () {
    test('delta.content', () {
      final e = parseSseDataPayload(
        '{"choices":[{"delta":{"content":"你"}}]}',
      );
      expect(e?.delta, '你');
      expect(e?.done, isFalse);
      expect(e?.toolCallDeltas, isEmpty);
    });

    test('[DONE]', () {
      final e = parseSseDataPayload('[DONE]');
      expect(e?.done, isTrue);
      expect(e?.delta, '');
    });

    test('坏 JSON 返回 null', () {
      expect(parseSseDataPayload('{"choices":'), isNull);
      expect(parseSseDataPayload('not-json'), isNull);
    });

    test('message.content 回退', () {
      final e = parseSseDataPayload(
        '{"choices":[{"message":{"content":"回退"}}]}',
      );
      expect(e?.delta, '回退');
    });

    test('text 回退', () {
      final e = parseSseDataPayload('{"choices":[{"text":"纯文本"}]}');
      expect(e?.delta, '纯文本');
    });

    test('流中 error 且无 choices 抛错', () {
      expect(
        () => parseSseDataPayload('{"error":{"message":"上游限流"}}'),
        throwsA(
          isA<ChatApiException>().having((e) => e.message, 'msg', contains('上游限流')),
        ),
      );
    });

    test('delta.tool_calls 与 content 可并存', () {
      final e = parseSseDataPayload(
        '{"choices":[{"delta":{"content":"查","tool_calls":['
        '{"index":0,"id":"call_1","type":"function","function":{"name":"lookup","arguments":"{\\"a\\":"}}'
        ']},"finish_reason":null}]}',
      );
      expect(e?.delta, '查');
      expect(e?.toolCallDeltas, hasLength(1));
      expect(e?.toolCallDeltas.single.id, 'call_1');
      expect(e?.toolCallDeltas.single.name, 'lookup');
      expect(e?.toolCallDeltas.single.argumentsDelta, '{"a":');
    });
  });

  group('ToolCallAccumulator', () {
    test('按 index 增量拼接 id/name/arguments', () {
      final acc = ToolCallAccumulator();
      acc.apply([
        const SseToolCallDelta(
          index: 0,
          id: 'call_a',
          type: 'function',
          name: 'lookup',
          argumentsDelta: '{"q":',
        ),
      ]);
      acc.apply([
        const SseToolCallDelta(
          index: 0,
          argumentsDelta: '"hi"}',
        ),
      ]);
      acc.apply([
        const SseToolCallDelta(
          index: 1,
          id: 'call_b',
          name: 'write',
          argumentsDelta: '{}',
        ),
      ]);
      final list = acc.snapshot();
      expect(list, hasLength(2));
      expect(list[0].id, 'call_a');
      expect(list[0].name, 'lookup');
      expect(list[0].arguments, '{"q":"hi"}');
      expect(list[1].id, 'call_b');
      expect(list[1].name, 'write');
    });
  });

  group('SseLineParser 分片', () {
    test('跨 chunk 拼接并忽略非 data', () {
      final parser = SseLineParser();
      final a = parser.addChunk('eve');
      expect(a, isEmpty);
      final b = parser.addChunk('nt: x\ndata: {"choices":[{"delta":{"content":"A"}}]}\n');
      expect(b.single.delta, 'A');
      final c = parser.addChunk('data: {"choices":[{"delta":{"content":"B"}}]}\ndata: [DONE]\n');
      expect(c[0].delta, 'B');
      expect(c[1].done, isTrue);
    });

    test('flush 残留', () {
      final parser = SseLineParser();
      parser.addChunk('data: {"choices":[{"delta":{"content":"Z"}}]}');
      final flushed = parser.flush();
      expect(flushed.single.delta, 'Z');
    });

    test('跨 chunk 的 tool_calls 增量', () {
      final parser = SseLineParser();
      final acc = ToolCallAccumulator();
      final e1 = parser.addChunk(
        'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","function":{"name":"f","arguments":"{"}}]}}]}\n',
      );
      acc.apply(e1.single.toolCallDeltas);
      final e2 = parser.addChunk(
        'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"}"}}]},"finish_reason":"tool_calls"}]}\n',
      );
      acc.apply(e2.single.toolCallDeltas);
      expect(e2.single.finishReason, 'tool_calls');
      expect(acc.snapshot().single.arguments, '{}');
    });
  });
}
