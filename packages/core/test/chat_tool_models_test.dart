import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatRole.tool', () {
    test('tryParse / wire', () {
      expect(ChatRole.tryParse('tool'), ChatRole.tool);
      expect(ChatRole.tool.wire, 'tool');
      expect(ChatRole.tryParse('TOOL'), ChatRole.tool);
    });
  });

  group('ChatToolCall JSON', () {
    test('toJson/fromJson 往返', () {
      const call = ChatToolCall(
        id: 'call_abc',
        name: 'biz.query',
        arguments: '{"id":1}',
      );
      final again = ChatToolCall.fromJson(call.toJson());
      expect(again, call);
      expect(again.toApiJson()['function'], {
        'name': 'biz.query',
        'arguments': '{"id":1}',
      });
    });

    test('兼容 OpenAI function 嵌套形态', () {
      final call = ChatToolCall.fromJson({
        'id': 'c1',
        'type': 'function',
        'function': {'name': 'fn', 'arguments': '{}'},
      });
      expect(call.name, 'fn');
      expect(call.arguments, '{}');
    });
  });

  group('ChatMessage tool 字段', () {
    test('assistant toolCalls 往返；旧 JSON 无字段不崩', () {
      const msg = ChatMessage(
        id: 'm1',
        createdAt: 1,
        role: ChatRole.assistant,
        content: '',
        toolCalls: [
          ChatToolCall(id: 'c1', name: 'lookup', arguments: '{}'),
        ],
      );
      final again = ChatMessage.fromJson(msg.toJson());
      expect(again.hasToolCalls, isTrue);
      expect(again.toolCalls.single.name, 'lookup');

      final legacy = ChatMessage.fromJson({
        'id': 'old',
        'createdAt': 0,
        'role': 'assistant',
        'content': 'hi',
      });
      expect(legacy.toolCalls, isEmpty);
      expect(legacy.toolCallId, isNull);
    });

    test('role=tool + toolCallId', () {
      const msg = ChatMessage(
        id: 't1',
        createdAt: 2,
        role: ChatRole.tool,
        content: 'result',
        toolCallId: 'c1',
      );
      final again = ChatMessage.fromJson(msg.toJson());
      expect(again.role, ChatRole.tool);
      expect(again.toolCallId, 'c1');

      final snake = ChatMessage.fromJson({
        'id': 't2',
        'createdAt': 0,
        'role': 'tool',
        'content': 'ok',
        'tool_call_id': 'c2',
      });
      expect(snake.toolCallId, 'c2');
    });
  });

  group('supportsChatTools', () {
    test('启发式与 force', () {
      expect(supportsChatTools('gpt-4o'), isTrue);
      expect(supportsChatTools('grok-4.5'), isTrue);
      expect(supportsChatTools('claude-sonnet-4'), isTrue);
      expect(supportsChatTools('dall-e-3'), isFalse);
      expect(supportsChatTools('text-embedding-3'), isFalse);
      expect(supportsChatTools('unknown-model'), isFalse);
      expect(supportsChatTools('unknown', force: true), isTrue);
      expect(supportsChatTools('gpt-4o', force: false), isFalse);
      expect(supportsChatTools(null), isFalse);
    });
  });
}
