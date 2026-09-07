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
  });
}
