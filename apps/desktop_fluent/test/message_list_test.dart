import 'package:core/core.dart';
import 'package:desktop_fluent/pages/chat/widgets/message_list.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';
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
  List<ChatMessage> messages,
) async {
  await tester.pumpWidget(
    FluentApp(
      theme: buildFluentLightTheme(),
      home: ScaffoldPage(
        content: MessageList(key: ValueKey(sessionId), messages: messages),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _tail =>
    find.textContaining('tail-marker', findRichText: true).hitTestable();

ScrollPosition _position(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first).position;

void main() {
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
      final position = _position(tester);
      position.jumpTo(500);
      await tester.pumpAndSettle();
      final readingOffset = position.pixels;

      await _pump(tester, 'chat', messages);
      expect(position.pixels, readingOffset);

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
}
