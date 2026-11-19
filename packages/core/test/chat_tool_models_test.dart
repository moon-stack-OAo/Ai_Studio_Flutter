import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'tool result status round-trips, projects, and stays out of API messages',
    () {
      for (final status in [
        McpToolCallStatus.success,
        McpToolCallStatus.failed,
        McpToolCallStatus.rejected,
        McpToolCallStatus.cancelled,
      ]) {
        final message = ChatMessage(
          id: 'tool',
          createdAt: 1,
          role: ChatRole.tool,
          content: 'result',
          toolCallId: 'call',
          toolResultStatus: status,
        );
        final restored = ChatMessage.fromJson(message.toJson());
        expect(restored.toolResultStatus, status);
        expect(restored.copyWith(content: 'new').toolResultStatus, status);
        expect(
          restored.copyWith(clearToolResultStatus: true).toolResultStatus,
          isNull,
        );
        final trace = buildToolRoundTraces(
          toolCalls: const [],
          toolResults: [restored],
        ).single;
        expect(trace.status, status);
        expect(buildApiMessages(history: [restored]), [
          {'role': 'tool', 'content': 'result', 'tool_call_id': 'call'},
        ]);
      }
    },
  );

  test(
    'legacy and unknown status compatible; content is not status metadata',
    () {
      final legacy = ChatMessage.fromJson({
        'id': 'old',
        'role': 'tool',
        'content': '示例：用户拒绝；策略拒绝',
        'toolResultStatus': 'future_status',
      });
      expect(legacy.toolResultStatus, isNull);
      expect(legacy.toJson().containsKey('toolResultStatus'), isFalse);
      ChatToolCallTrace project(ChatMessage m) =>
          buildToolRoundTraces(toolCalls: const [], toolResults: [m]).single;
      expect(project(legacy).status, McpToolCallStatus.success);
      expect(
        project(legacy.copyWith(error: true)).status,
        McpToolCallStatus.failed,
      );
      expect(
        project(legacy.copyWith(stopped: true)).status,
        McpToolCallStatus.cancelled,
      );
    },
  );

  test('repository persists only optional enum metadata', () async {
    final storage = MemoryChatSessionStorage();
    final repo = ChatSessionRepository(storage: storage);
    await repo.load();
    for (final status in [
      McpToolCallStatus.success,
      McpToolCallStatus.failed,
      McpToolCallStatus.rejected,
      McpToolCallStatus.cancelled,
    ]) {
      await repo.appendMessage(
        repo.activeId,
        role: ChatRole.tool,
        content: 'existing content',
        toolCallId: status.wire,
        toolResultStatus: status,
      );
    }
    final restored = ChatSessionRepository(storage: storage);
    await restored.load();
    expect(restored.activeSession!.messages.map((m) => m.toolResultStatus), [
      McpToolCallStatus.success,
      McpToolCallStatus.failed,
      McpToolCallStatus.rejected,
      McpToolCallStatus.cancelled,
    ]);
    repo.dispose();
    restored.dispose();
  });

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
        toolCalls: [ChatToolCall(id: 'c1', name: 'lookup', arguments: '{}')],
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
    test('Agnes 对话模型支持 tools，媒体型号不挂载工具', () {
      expect(supportsChatTools('agnes-2.0-flash'), isTrue);
      expect(supportsChatTools('agnes-2.5-flash'), isTrue);
      expect(supportsChatTools('  AgnesAI/AGNES-2.5-FLASH  '), isTrue);
      expect(supportsChatTools('agnes-image-2.0-flash'), isFalse);
      expect(supportsChatTools('agnes-image-2.1-flash'), isFalse);
      expect(supportsChatTools('AgnesAI/AGNES-VIDEO-V2.0'), isFalse);
    });

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
