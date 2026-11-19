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

ChatToolCallTrace _live(String id, McpToolCallStatus status) =>
    ChatToolCallTrace(
      toolCallId: id,
      serverId: 'server',
      serverDisplayName: 'Server',
      toolName: 'live-$id',
      status: status,
    );

void main() {
  test('tool-chain pauses stay in one stable group across stream stages', () {
    final history = [
      _msg(
        id: 'a1',
        role: ChatRole.assistant,
        toolCalls: const [ChatToolCall(id: 'c1', name: 'one')],
      ),
      _msg(id: 't1', role: ChatRole.tool, toolCallId: 'c1', content: 'ok'),
    ];
    final initial =
        groupChatMessagesForDisplay(history).single as ChatDisplayToolRound;
    final wait = _msg(
      id: 'a2',
      role: ChatRole.assistant,
      content: ' \n ',
    ).copyWith(streaming: true);
    final paused = groupChatMessagesForDisplay([...history, wait]);
    expect(paused, hasLength(1));
    expect((paused.single as ChatDisplayToolRound).groupId, initial.groupId);

    // 下一轮仍在 streaming 且仅有 toolCalls 时，不应先冒出空气泡。
    final nextCall = wait.copyWith(
      toolCalls: const [ChatToolCall(id: 'c2', name: 'two')],
    );
    final calling = groupChatMessagesForDisplay(
      [...history, nextCall],
      liveTraces: [
        _live('c1', McpToolCallStatus.success),
        _live('c2', McpToolCallStatus.queued),
        _live('c2', McpToolCallStatus.running),
      ],
    );
    expect(calling, hasLength(1));
    final callingRound = calling.single as ChatDisplayToolRound;
    expect(callingRound.groupId, initial.groupId);
    expect(callingRound.traces.map((t) => t.toolCallId), ['c1', 'c2']);
    expect(callingRound.traces.last.status, McpToolCallStatus.running);

    final persisted = [
      ...history,
      nextCall.copyWith(streaming: false),
      _msg(id: 't2', role: ChatRole.tool, toolCallId: 'c2', content: 'done'),
    ];
    final waitingAgain = groupChatMessagesForDisplay([
      ...persisted,
      wait.copyWith(id: 'a3'),
    ]);
    final completedRound = waitingAgain.single as ChatDisplayToolRound;
    expect(completedRound.groupId, initial.groupId);
    expect(completedRound.traces.map((t) => t.toolCallId), ['c1', 'c2']);
    expect(completedRound.traces.last.status, McpToolCallStatus.success);

    // 同一占位收到真实正文后立即展示，后续工具不得跨越它合并。
    final body = wait.copyWith(id: 'a3', content: '继续说明');
    final withBody = groupChatMessagesForDisplay([...persisted, body]);
    expect(withBody, hasLength(2));
    expect((withBody.last as ChatDisplayMessage).message, same(body));
    final afterBody = groupChatMessagesForDisplay([
      ...persisted,
      body.copyWith(streaming: false),
      _msg(
        id: 'a4',
        role: ChatRole.assistant,
        toolCalls: const [ChatToolCall(id: 'c3', name: 'three')],
      ).copyWith(streaming: true),
    ]);
    expect(afterBody, hasLength(3));
    expect((afterBody.first as ChatDisplayToolRound).groupId, initial.groupId);
    expect(
      (afterBody.last as ChatDisplayToolRound).traces.single.toolCallId,
      'c3',
    );
    expect(history, hasLength(2));
    expect(wait.streaming, isTrue);
  });

  test('initial request wait survives even after an earlier tool turn', () {
    final wait = _msg(
      id: 'wait',
      role: ChatRole.assistant,
    ).copyWith(streaming: true);
    expect(
      groupChatMessagesForDisplay([wait]).single,
      isA<ChatDisplayMessage>(),
    );
    final items = groupChatMessagesForDisplay([
      _msg(
        id: 'old',
        role: ChatRole.assistant,
        toolCalls: const [ChatToolCall(id: 'old-call', name: 'old')],
      ),
      _msg(id: 'user', role: ChatRole.user, content: '新请求'),
      wait,
    ]);
    expect(items, hasLength(3));
    expect((items.last as ChatDisplayMessage).message, same(wait));
  });

  test(
    'failed and stopped tool-chain waits become visible hard boundaries',
    () {
      final call = _msg(
        id: 'a1',
        role: ChatRole.assistant,
        toolCalls: const [ChatToolCall(id: 'c1', name: 'one')],
      );
      final wait = _msg(
        id: 'wait',
        role: ChatRole.assistant,
      ).copyWith(streaming: true);
      final history = [
        call,
        _msg(id: 't1', role: ChatRole.tool, toolCallId: 'c1', content: 'ok'),
      ];
      expect(groupChatMessagesForDisplay([...history, wait]), hasLength(1));
      for (final streaming in [false, true]) {
        for (final terminal in [
          wait.copyWith(
            streaming: streaming,
            error: true,
            errorMessage: 'failed',
          ),
          wait.copyWith(streaming: streaming, stopped: true),
        ]) {
          for (final withCalls in [false, true]) {
            final message = terminal.copyWith(
              toolCalls: withCalls
                  ? const [ChatToolCall(id: 'c2', name: 'two')]
                  : const [],
            );
            final items = groupChatMessagesForDisplay([
              ...history,
              message,
              if (!withCalls)
                _msg(
                  id: 'a2',
                  role: ChatRole.assistant,
                  toolCalls: const [ChatToolCall(id: 'c2', name: 'two')],
                ),
            ]);
            expect(items, hasLength(3));
            expect((items[1] as ChatDisplayMessage).message, same(message));
            expect(items.first, isA<ChatDisplayToolRound>());
            expect(items.last, isA<ChatDisplayToolRound>());
          }
        }
      }
    },
  );

  test(
    'empty assistant attachments are preserved with or without tool calls',
    () {
      const attachment = ImageRef(
        type: ImageRefType.url,
        src: 'https://a.test/a.png',
      );
      for (final streaming in [false, true]) {
        for (final withCalls in [false, true]) {
          final attachmentMessage = _msg(
            id: 'image',
            role: ChatRole.assistant,
            content: ' ',
            toolCalls: withCalls
                ? const [ChatToolCall(id: 'c2', name: 'two')]
                : const [],
          ).copyWith(streaming: streaming, attachments: const [attachment]);
          final items = groupChatMessagesForDisplay([
            _msg(
              id: 'a1',
              role: ChatRole.assistant,
              toolCalls: const [ChatToolCall(id: 'c1', name: 'one')],
            ),
            attachmentMessage,
            if (!withCalls)
              _msg(
                id: 'a2',
                role: ChatRole.assistant,
                toolCalls: const [ChatToolCall(id: 'c2', name: 'two')],
              ),
          ]);
          expect(items, hasLength(3));
          final bubble = items[1] as ChatDisplayMessage;
          expect(bubble.message, same(attachmentMessage));
          expect(bubble.message.attachments.single, same(attachment));
          expect(bubble.hideToolCallsStrip, withCalls);
        }
      }
    },
  );

  test(
    'live overlays historical position; last update wins; body is a boundary',
    () {
      final history = [
        _msg(
          id: 'a1',
          role: ChatRole.assistant,
          toolCalls: const [ChatToolCall(id: 'c1', name: 'one')],
        ),
        _msg(id: 'body', role: ChatRole.assistant, content: '正文'),
        _msg(id: 't1', role: ChatRole.tool, toolCallId: 'c1', content: 'late'),
        _msg(
          id: 'a2',
          role: ChatRole.assistant,
          toolCalls: const [ChatToolCall(id: 'c2', name: 'two')],
        ),
      ];
      final items = groupChatMessagesForDisplay(
        history,
        liveTraces: [
          _live('c2', McpToolCallStatus.running),
          _live('c1', McpToolCallStatus.pendingAuth),
          _live('c3', McpToolCallStatus.queued),
          _live('c1', McpToolCallStatus.failed),
        ],
      );
      expect(items, hasLength(3));
      final first = items[0] as ChatDisplayToolRound;
      expect(first.traces.single.toolCallId, 'c1');
      expect(first.traces.single.status, McpToolCallStatus.failed);
      expect(first.traces.single.resultSummary, isNull);
      expect((items[1] as ChatDisplayMessage).message.id, 'body');
      final last = items[2] as ChatDisplayToolRound;
      expect(last.traces.map((t) => t.toolCallId), ['c2', 'c3']);
      expect(last.traces.first.status, McpToolCallStatus.running);
      expect(history, hasLength(4));
    },
  );

  test(
    'only adjacent tool rounds merge; every message role is a hard boundary',
    () {
      for (final role in [ChatRole.user, ChatRole.assistant, ChatRole.system]) {
        final items = groupChatMessagesForDisplay([
          for (final id in ['c1', 'c2'])
            _msg(
              id: 'a$id',
              role: ChatRole.assistant,
              toolCalls: [ChatToolCall(id: id, name: id)],
            ),
          _msg(id: 'boundary', role: role, content: '正文'),
          _msg(
            id: 'a3',
            role: ChatRole.assistant,
            content: '先说明',
            toolCalls: const [ChatToolCall(id: 'c3', name: 'three')],
          ),
        ]);
        expect(items, hasLength(4));
        expect(
          (items[0] as ChatDisplayToolRound).traces.map((t) => t.toolCallId),
          ['c1', 'c2'],
        );
        expect(items[1], isA<ChatDisplayMessage>());
        expect(items[2], isA<ChatDisplayMessage>());
        expect(
          (items[3] as ChatDisplayToolRound).traces.single.toolCallId,
          'c3',
        );
      }
    },
  );

  test('live-only group key survives updates, appends and persistence', () {
    final before =
        groupChatMessagesForDisplay(
              [],
              liveTraces: [_live('c1', McpToolCallStatus.pendingAuth)],
            ).single
            as ChatDisplayToolRound;
    final after =
        groupChatMessagesForDisplay(
              [
                _msg(
                  id: 'a1',
                  role: ChatRole.assistant,
                  toolCalls: const [ChatToolCall(id: 'c1', name: 'one')],
                ),
              ],
              liveTraces: [
                _live('c1', McpToolCallStatus.success),
                _live('c2', McpToolCallStatus.running),
              ],
            ).single
            as ChatDisplayToolRound;
    expect(before.groupId, 'tool-group:call:c1');
    expect(after.groupId, before.groupId);
    expect(after.anchorMessageId, 'a1');
    expect(after.traces, hasLength(2));
  });

  test(
    'missing result is conservative; late historical result restores status',
    () {
      final call = _msg(
        id: 'a',
        role: ChatRole.assistant,
        toolCalls: const [ChatToolCall(id: 'c', name: 'query')],
      );
      final missing =
          (groupChatMessagesForDisplay([call]).single as ChatDisplayToolRound)
              .traces
              .single;
      expect(missing.status, McpToolCallStatus.queued);
      expect(missing.resultSummary, '历史记录缺少工具结果');
      final items = groupChatMessagesForDisplay([
        call,
        _msg(id: 'body', role: ChatRole.assistant, content: '正文'),
        _msg(id: 'result', role: ChatRole.tool, toolCallId: 'c', content: 'ok'),
      ]);
      expect(items, hasLength(2));
      expect(
        (items.first as ChatDisplayToolRound).traces.single.status,
        McpToolCallStatus.success,
      );
      expect(items.last, isA<ChatDisplayMessage>());
    },
  );

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
      _msg(id: 't2', role: ChatRole.tool, content: 'ok', toolCallId: 'c2'),
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
