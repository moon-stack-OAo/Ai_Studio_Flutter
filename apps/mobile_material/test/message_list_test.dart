import 'package:core/core.dart';
import 'package:mobile_material/pages/chat/widgets/message_list.dart';
import 'package:mobile_material/pages/chat/widgets/markdown_host.dart';
import 'package:mobile_material/pages/chat/widgets/tool_call_trace_card.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

String _table(String marker) => [
  '| Column | Value |',
  '| --- | --- |',
  for (var i = 0; i < 60; i++) '| Row $i | A long table value $i |',
  '',
  marker,
].join('\n');

List<ChatMessage> _history(String prefix, {bool tableAtEnd = false}) => [
  for (var i = 0; i < 40; i++)
    ChatMessage(
      id: '$prefix-$i',
      createdAt: i,
      role: i.isEven ? ChatRole.user : ChatRole.assistant,
      content: i == 39
          ? (tableAtEnd ? _table('tail-marker') : 'tail-marker')
          : (i % 5 == 0
                ? _table('table-end-$i')
                : List.filled(12, 'Long history message $i.').join('\n')),
    ),
];

Future<void> _pump(
  WidgetTester tester,
  String sessionId,
  List<ChatMessage> messages, {
  bool settle = true,
  List<ChatToolCallTrace> liveToolTraces = const [],
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildMaterialLightTheme(),
      home: Scaffold(
        body: MessageList(
          key: ValueKey(sessionId),
          messages: messages,
          liveToolTraces: liveToolTraces,
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 64));
  }
}

Finder get _tail =>
    find.textContaining('tail-marker', findRichText: true).hitTestable();

ScrollPosition _position(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first).position;

List<ChatMessage> _delta(List<ChatMessage> messages, int tick) => [
  ...messages.take(messages.length - 1),
  messages.last.copyWith(
    streaming: true,
    content: List.filled(12 + tick, 'Streaming line $tick.').join('\n'),
  ),
];

const _trace = ChatToolCallTrace(
  toolCallId: 'live-call',
  serverId: 'server',
  serverDisplayName: 'Server',
  toolName: 'search',
  status: McpToolCallStatus.success,
);

Future<void> _wheelUp(WidgetTester tester) async {
  await tester.sendEventToBinding(
    PointerScrollEvent(
      position: tester.getCenter(find.byType(ListView)),
      scrollDelta: const Offset(0, -240),
    ),
  );
  await tester.pump(const Duration(milliseconds: 64));
}

void main() {
  testWidgets('live overlays history in place, with body as hard boundary', (
    tester,
  ) async {
    const messages = [
      ChatMessage(
        id: 'invoke',
        createdAt: 1,
        role: ChatRole.assistant,
        content: '',
        toolCalls: [
          ChatToolCall(id: 'live-call', name: 'search', arguments: '{}'),
        ],
      ),
      ChatMessage(
        id: 'result',
        createdAt: 2,
        role: ChatRole.tool,
        toolCallId: 'live-call',
        content: 'old-result',
      ),
      ChatMessage(
        id: 'body',
        createdAt: 3,
        role: ChatRole.assistant,
        content: 'body-boundary',
      ),
    ];
    await _pump(
      tester,
      'overlay',
      messages,
      liveToolTraces: [
        _trace.copyWith(resultSummary: 'live-result'),
        const ChatToolCallTrace(
          toolCallId: 'other',
          serverId: 'server',
          serverDisplayName: 'Server',
          toolName: 'other-tool',
          status: McpToolCallStatus.success,
        ),
      ],
    );
    expect(find.byType(ToolCallTraceGroup), findsNWidgets(2));
    for (final toggle
        in find
            .byKey(const ValueKey('tool-group-toggle'))
            .evaluate()
            .toList()) {
      await tester.tap(find.byWidget(toggle.widget));
      await tester.pumpAndSettle();
    }
    expect(find.text('live-result'), findsOneWidget);
    expect(find.text('old-result'), findsNothing);
    expect(
      tester.getTopLeft(find.text('live-result')).dy,
      lessThan(tester.getTopLeft(find.text('body-boundary')).dy),
    );
    expect(
      tester.getTopLeft(find.text('body-boundary')).dy,
      lessThan(tester.getTopLeft(find.text('other-tool')).dy),
    );
  });

  testWidgets(
    'expansion survives live persistence, offscreen disposal and is session isolated',
    (tester) async {
      await _pump(
        tester,
        'persist',
        const [],
        liveToolTraces: [
          _trace.copyWith(argumentsSummary: 'args', resultSummary: 'result'),
        ],
      );
      await tester.tap(find.byKey(const ValueKey('tool-group-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('参数摘要（脱敏'));
      await tester.pumpAndSettle();
      const persisted = [
        ChatMessage(
          id: 'invoke',
          createdAt: 1,
          role: ChatRole.assistant,
          content: '',
          toolCalls: [
            ChatToolCall(id: 'live-call', name: 'search', arguments: '{}'),
          ],
        ),
        ChatMessage(
          id: 'result',
          createdAt: 2,
          role: ChatRole.tool,
          toolCallId: 'live-call',
          content: 'saved-result',
        ),
      ];
      await _pump(tester, 'persist', persisted);
      expect(find.text('复制参数摘要'), findsOneWidget);
      final long = [...persisted, ..._history('later')];
      await _pump(tester, 'persist', long);
      _position(tester).jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.byType(ToolCallTraceGroup), findsNothing);
      await tester.scrollUntilVisible(
        find.byType(ToolCallTraceGroup),
        600,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 100,
      );
      await tester.pumpAndSettle();
      expect(find.text('复制参数摘要'), findsOneWidget);
      await _pump(tester, 'different-session', persisted);
      expect(find.text('复制参数摘要'), findsNothing);
      expect(find.textContaining('参数摘要（脱敏'), findsNothing);
    },
  );
  testWidgets('opening long history shows the last message', (tester) async {
    await _pump(tester, 'long', _history('long'));
    expect(_tail, findsOneWidget);
  });

  testWidgets('opening a tall final table shows its end', (tester) async {
    await _pump(tester, 'table', _history('table', tableAtEnd: true));
    expect(_tail, findsOneWidget);
  });

  testWidgets(
    'switching equal-length chats with identical tails returns to bottom',
    (tester) async {
      await _pump(tester, 'first', _history('first'));
      final firstPosition = _position(tester);
      firstPosition.jumpTo(firstPosition.maxScrollExtent / 2);
      await tester.pumpAndSettle();
      expect(_tail, findsNothing);

      await _pump(tester, 'second', _history('second', tableAtEnd: true));
      expect(_tail, findsOneWidget);

      await _pump(tester, 'first', _history('first'));
      expect(_tail, findsOneWidget);
    },
  );

  testWidgets(
    'new messages reach bottom; unrelated rebuild keeps reading position',
    (tester) async {
      final messages = _history('chat');
      await _pump(tester, 'chat', messages);
      _position(tester).jumpTo(500);
      await tester.pumpAndSettle();
      final readingOffset = _position(tester).pixels;

      await _pump(tester, 'chat', messages);
      expect(_position(tester).pixels, readingOffset);

      await _pump(tester, 'chat', [
        ...messages,
        const ChatMessage(
          id: 'new',
          createdAt: 100,
          role: ChatRole.user,
          content: 'new-message-marker',
        ),
      ]);
      expect(find.text('new-message-marker').hitTestable(), findsOneWidget);
      expect(_position(tester).pixels, 0);
    },
  );

  testWidgets('messages remain in chronological visual order', (tester) async {
    await _pump(tester, 'short', const [
      ChatMessage(
        id: 'old',
        createdAt: 1,
        role: ChatRole.user,
        content: 'older',
      ),
      ChatMessage(
        id: 'new',
        createdAt: 2,
        role: ChatRole.user,
        content: 'newer',
      ),
    ]);
    expect(
      tester.getTopLeft(find.text('older')).dy,
      lessThan(tester.getTopLeft(find.text('newer')).dy),
    );
  });

  testWidgets('wheel reading survives deltas, tool updates and stream end', (
    tester,
  ) async {
    final history = _history('stream');
    await _pump(tester, 'stream', _delta(history, 0), settle: false);
    await _wheelUp(tester);
    final readingOffset = _position(tester).pixels;
    expect(readingOffset, greaterThan(100));

    for (var tick = 1; tick <= 4; tick++) {
      await _pump(
        tester,
        'stream',
        _delta(history, tick),
        settle: false,
        liveToolTraces: [
          _trace.copyWith(
            status: tick.isOdd
                ? McpToolCallStatus.running
                : McpToolCallStatus.success,
            resultSummary: 'Result $tick',
          ),
        ],
      );
      // 每次读取当前 position，Material 主题重建可能替换实例。
      expect(_position(tester).pixels, closeTo(readingOffset, 1));
    }
    final complete = _delta(history, 4);
    complete[complete.length - 1] = complete.last.copyWith(streaming: false);
    await _pump(tester, 'stream', complete);
    expect(_position(tester).pixels, closeTo(readingOffset, 1));
    await _pump(tester, 'stream', [
      ...complete,
      const ChatMessage(
        id: 'next-assistant',
        createdAt: 101,
        role: ChatRole.assistant,
        content: 'Additional assistant message',
      ),
    ]);
    expect(_position(tester).pixels, closeTo(readingOffset, 1));
    // 撤回/删除末条也不能恢复自动跟随。
    await _pump(tester, 'stream', complete);
    expect(_position(tester).pixels, closeTo(readingOffset, 1));
    await _pump(tester, 'stream', [
      ...complete,
      const ChatMessage(
        id: 'sent-user',
        createdAt: 102,
        role: ChatRole.user,
        content: 'Send while reading',
      ),
    ]);
    expect(_position(tester).pixels, 0);
    expect(find.text('Send while reading').hitTestable(), findsOneWidget);
  });

  testWidgets('drag interrupts follow and returning to bottom resumes it', (
    tester,
  ) async {
    final history = _history('drag');
    await _pump(tester, 'drag', _delta(history, 0), settle: false);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ListView)),
    );
    await gesture.moveBy(const Offset(0, 180));
    await tester.pump(const Duration(milliseconds: 64));
    final readingOffset = _position(tester).pixels;
    expect(readingOffset, greaterThan(100));

    await _pump(tester, 'drag', _delta(history, 1), settle: false);
    expect(_position(tester).pixels, closeTo(readingOffset, 1));
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump(const Duration(milliseconds: 64));
    expect(_position(tester).pixels, greaterThan(readingOffset + 40));
    await gesture.up();
    await tester.pump(const Duration(seconds: 1));

    // 底部容差内恢复跟随，下一帧精确归零，无反复驱动的滚动动画。
    _position(tester).jumpTo(0.5);
    await tester.pump();
    for (var tick = 2; tick <= 4; tick++) {
      await _pump(tester, 'drag', _delta(history, tick), settle: false);
      expect(_position(tester).pixels, 0);
      expect(_position(tester).isScrollingNotifier.value, isFalse);
    }
  });

  testWidgets('visible Markdown state survives assistant and live insertion', (
    tester,
  ) async {
    final messages = _history('state');
    await _pump(tester, 'state', messages);
    _position(tester).jumpTo(400);
    await tester.pumpAndSettle();
    final host = find.byType(MarkdownHost).hitTestable().first;
    final hostKey = tester.widget<MarkdownHost>(host).key!;
    final state = tester.state(host);
    final appended = [
      ...messages,
      const ChatMessage(
        id: 'inserted',
        createdAt: 101,
        role: ChatRole.assistant,
        content: 'New reply',
      ),
    ];
    await _pump(tester, 'state', appended, liveToolTraces: [_trace]);
    expect(tester.state(find.byKey(hostKey)), same(state));
    expect(state.mounted, isTrue);
    await _pump(tester, 'state', appended);
    expect(tester.state(find.byKey(hostKey)), same(state));
  });

  testWidgets(
    'adjacent live and history share a stable group across index changes',
    (tester) async {
      const messages = [
        ChatMessage(
          id: 'tool-assistant',
          createdAt: 1,
          role: ChatRole.assistant,
          content: '',
          toolCalls: [
            ChatToolCall(id: 'call', name: 'search', arguments: '{}'),
          ],
        ),
        ChatMessage(
          id: 'tool-result',
          createdAt: 2,
          role: ChatRole.tool,
          toolCallId: 'call',
          content: 'Result',
        ),
      ];
      await _pump(tester, 'tools', messages, liveToolTraces: [_trace]);
      final groups = find.byType(ToolCallTraceGroup);
      expect(groups, findsOneWidget);
      final groupState = tester.state(groups);
      await tester.tap(find.byKey(const ValueKey('tool-group-toggle')));
      await tester.pumpAndSettle();
      await _pump(tester, 'tools', [
        ...messages,
        const ChatMessage(
          id: 'answer',
          createdAt: 3,
          role: ChatRole.assistant,
          content: 'Answer',
        ),
      ]);
      expect(groups, findsOneWidget);
      expect(tester.state(groups), same(groupState));
      expect(find.byType(ToolCallTraceCard), findsOneWidget);
    },
  );
}
