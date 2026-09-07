import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatChatLatency', () {
    test('<1秒用毫秒', () {
      expect(formatChatLatency(0), '0毫秒');
      expect(formatChatLatency(850), '850毫秒');
      expect(formatChatLatency(999), '999毫秒');
    });

    test('<60秒用整秒', () {
      expect(formatChatLatency(1000), '1秒');
      expect(formatChatLatency(52000), '52秒');
      expect(formatChatLatency(59999), '59秒');
    });

    test('≥60秒用x分x秒；整分省略0秒', () {
      expect(formatChatLatency(60000), '1分');
      expect(formatChatLatency(83000), '1分23秒');
      expect(formatChatLatency(125000), '2分5秒');
    });

    test('负值按0处理', () {
      expect(formatChatLatency(-10), '0毫秒');
    });
  });

  group('formatChatMessageMeta', () {
    test('完成态：模型 · 耗时', () {
      expect(
        formatChatMessageMeta(model: 'grok-4.5', latencyMs: 52000),
        'grok-4.5 · 52秒',
      );
    });

    test('流式中仅显模型', () {
      expect(
        formatChatMessageMeta(
          model: 'grok-4.5',
          latencyMs: 100,
          streaming: true,
        ),
        'grok-4.5',
      );
    });

    test('无模型无耗时返回 null', () {
      expect(formatChatMessageMeta(), isNull);
      expect(formatChatMessageMeta(streaming: true), isNull);
    });

    test('仅耗时', () {
      expect(formatChatMessageMeta(latencyMs: 850), '850毫秒');
    });
  });

  group('ChatMessage model/latencyMs JSON', () {
    test('往返保留字段', () {
      const msg = ChatMessage(
        id: 'm1',
        createdAt: 1,
        role: ChatRole.assistant,
        content: 'hi',
        model: 'grok-4.5',
        latencyMs: 1234,
      );
      final again = ChatMessage.fromJson(msg.toJson());
      expect(again.model, 'grok-4.5');
      expect(again.latencyMs, 1234);
    });

    test('旧消息缺字段兼容', () {
      final msg = ChatMessage.fromJson({
        'id': 'm2',
        'createdAt': 2,
        'role': 'assistant',
        'content': 'old',
      });
      expect(msg.model, isNull);
      expect(msg.latencyMs, isNull);
      final json = msg.toJson();
      expect(json.containsKey('model'), isFalse);
      expect(json.containsKey('latencyMs'), isFalse);
    });
  });
}
