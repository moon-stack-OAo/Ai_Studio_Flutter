import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

ChatMessage _msg(ChatRole role, String content, {String? id}) => ChatMessage(
      id: id ?? createId('msg'),
      createdAt: 1,
      role: role,
      content: content,
    );

void main() {
  test('保留全部 system + 最近 N 轮', () {
    final msgs = <ChatMessage>[
      _msg(ChatRole.system, 'sys'),
      for (var i = 1; i <= 5; i++) ...[
        _msg(ChatRole.user, 'u$i'),
        _msg(ChatRole.assistant, 'a$i'),
      ],
    ];
    final result = trimChatMessages(msgs, maxTurns: 2);
    expect(result.truncated, isTrue);
    expect(result.keptTurns, 2);
    expect(result.droppedTurns, 3);
    expect(result.messages.first.role, ChatRole.system);
    expect(result.messages.where((m) => m.role == ChatRole.user).map((m) => m.content),
        ['u4', 'u5']);
  });

  test('未超限不裁剪', () {
    final msgs = [
      _msg(ChatRole.user, 'u1'),
      _msg(ChatRole.assistant, 'a1'),
    ];
    final result = trimChatMessages(msgs, maxTurns: 5);
    expect(result.truncated, isFalse);
    expect(result.messages.length, 2);
  });

  test('enabled:false 保留全部', () {
    final msgs = [
      for (var i = 1; i <= 4; i++) ...[
        _msg(ChatRole.user, 'u$i'),
        _msg(ChatRole.assistant, 'a$i'),
      ],
    ];
    final result = trimChatMessages(msgs, enabled: false, maxTurns: 1);
    expect(result.truncated, isFalse);
    expect(result.messages.length, 8);
  });

  test('字符预算丢最旧轮', () {
    final msgs = [
      _msg(ChatRole.system, 's'),
      _msg(ChatRole.user, 'aaaa'),
      _msg(ChatRole.assistant, 'bbbb'),
      _msg(ChatRole.user, 'c'),
      _msg(ChatRole.assistant, 'd'),
    ];
    final result = trimChatMessages(
      msgs,
      maxTurns: 10,
      maxCharsEnabled: true,
      maxChars: 10,
    );
    expect(result.truncatedByChars, isTrue);
    expect(result.keptTurns, lessThanOrEqualTo(2));
    expect(result.messages.any((m) => m.role == ChatRole.system), isTrue);
  });

  test('buildApiMessages system 前置', () {
    final history = [
      _msg(ChatRole.user, 'hi'),
      _msg(ChatRole.assistant, 'yo'),
      _msg(ChatRole.system, 'ignored-in-history'),
    ];
    final api = buildApiMessages(history: history, systemPrompt: '  规则  ');
    expect(api.first, {'role': 'system', 'content': '规则'});
    expect(api.length, 3);
    expect(api[1]['role'], 'user');
    expect(api[2]['role'], 'assistant');
  });

  test('buildApiMessages 含 tool_calls 与 role=tool', () {
    final history = [
      _msg(ChatRole.user, '查一下'),
      ChatMessage(
        id: 'a1',
        createdAt: 1,
        role: ChatRole.assistant,
        content: '',
        toolCalls: const [
          ChatToolCall(id: 'call_1', name: 'lookup', arguments: '{"q":1}'),
        ],
      ),
      const ChatMessage(
        id: 't1',
        createdAt: 2,
        role: ChatRole.tool,
        content: '{"ok":true}',
        toolCallId: 'call_1',
      ),
      _msg(ChatRole.assistant, '结果如下'),
    ];
    final api = buildApiMessages(history: history);
    expect(api.length, 4);
    expect(api[1]['tool_calls'], isA<List>());
    expect((api[1]['tool_calls'] as List).single['id'], 'call_1');
    expect(api[2], {
      'role': 'tool',
      'content': '{"ok":true}',
      'tool_call_id': 'call_1',
    });
  });

  test('裁剪整轮丢弃，不留孤立 tool', () {
    final msgs = [
      _msg(ChatRole.user, 'u1'),
      ChatMessage(
        id: 'a1',
        createdAt: 1,
        role: ChatRole.assistant,
        content: '',
        toolCalls: const [
          ChatToolCall(id: 'c1', name: 'f', arguments: '{}'),
        ],
      ),
      const ChatMessage(
        id: 't1',
        createdAt: 2,
        role: ChatRole.tool,
        content: 'r1',
        toolCallId: 'c1',
      ),
      _msg(ChatRole.assistant, 'done1'),
      _msg(ChatRole.user, 'u2'),
      _msg(ChatRole.assistant, 'a2'),
    ];
    final result = trimChatMessages(msgs, maxTurns: 1);
    expect(result.keptTurns, 1);
    expect(result.messages.any((m) => m.role == ChatRole.tool), isFalse);
    expect(result.messages.map((m) => m.content), ['u2', 'a2']);
  });
}
