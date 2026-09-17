import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

ChatMessage _msg({
  required String id,
  required ChatRole role,
  String content = '',
  List<ChatToolCall> toolCalls = const [],
  String? toolCallId,
}) {
  return ChatMessage(
    id: id,
    createdAt: 1,
    role: role,
    content: content,
    toolCalls: toolCalls,
    toolCallId: toolCallId,
  );
}

void main() {
  test('groups assistant tool_calls with following tool results', () {
    final items = groupChatMessagesForDisplay([
      _msg(id: 'u1', role: ChatRole.user, content: '退款'),
      _msg(
        id: 'a1',
        role: ChatRole.assistant,
        content: '好的，我先查订单。',
        toolCalls: const [
          ChatToolCall(id: 'c1', name: 'biz.order.list', arguments: '{}'),
          ChatToolCall(
            id: 'c2',
            name: 'biz.order.refund',
            arguments: '{"id":"1"}',
          ),
        ],
      ),
      _msg(
        id: 't1',
        role: ChatRole.tool,
        content: '[{"id":"1"}]',
        toolCallId: 'c1',
      ),
      _msg(
        id: 't2',
        role: ChatRole.tool,
        content: 'ok',
        toolCallId: 'c2',
      ),
      _msg(id: 'a2', role: ChatRole.assistant, content: '已完成退款。'),
    ]);

    expect(items.length, 4);
    expect(items[0], isA<ChatDisplayMessage>());
    expect((items[0] as ChatDisplayMessage).message.id, 'u1');

    expect(items[1], isA<ChatDisplayMessage>());
    final a1 = items[1] as ChatDisplayMessage;
    expect(a1.message.id, 'a1');
    expect(a1.hideToolCallsStrip, isTrue);

    expect(items[2], isA<ChatDisplayToolRound>());
    final round = items[2] as ChatDisplayToolRound;
    expect(round.traces.length, 2);
    expect(round.traces[0].toolName, 'biz.order.list');
    expect(round.traces[1].toolName, 'biz.order.refund');

    expect(items[3], isA<ChatDisplayMessage>());
    expect((items[3] as ChatDisplayMessage).message.id, 'a2');
  });

  test('tool-only assistant message collapses to round only', () {
    final items = groupChatMessagesForDisplay([
      _msg(
        id: 'a1',
        role: ChatRole.assistant,
        toolCalls: const [
          ChatToolCall(id: 'c1', name: 'ping', arguments: '{}'),
        ],
      ),
      _msg(id: 't1', role: ChatRole.tool, content: 'pong', toolCallId: 'c1'),
    ]);
    expect(items.length, 1);
    expect(items.single, isA<ChatDisplayToolRound>());
  });
}
