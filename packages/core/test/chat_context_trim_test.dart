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
}
