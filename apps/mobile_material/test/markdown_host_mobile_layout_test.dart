import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_material/pages/chat/widgets/markdown_host.dart';
import 'package:mobile_material/pages/chat/widgets/message_bubble.dart';

void main() {
  testWidgets('窄屏 Markdown 表格可横滑且助手气泡更接近满宽', (tester) async {
    const narrowWidth = 360.0;

    const tableMd = '''
## 窄屏标题

- 列表一项
- 列表二项

| Col A | Col B | Col C | Col D |
| --- | --- | --- | --- |
| alpha-value-1 | beta-value-2 | gamma-value-3 | delta-value-4 |
| longer-cell-content-aaaa | longer-cell-content-bbbb | longer-cell-content-cccc | longer-cell-content-dddd |
''';

    await tester.pumpWidget(
      MaterialApp(
        theme: buildMaterialLightTheme(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(narrowWidth, 720)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: MessageBubble(
                message: ChatMessage(
                  id: 'md-mobile',
                  createdAt: 1,
                  role: ChatRole.assistant,
                  content: tableMd,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownHost), findsOneWidget);
    expect(find.textContaining('窄屏标题', findRichText: true), findsOneWidget);

    final bubbleBox = tester
        .widgetList<ConstrainedBox>(find.byType(ConstrainedBox))
        .firstWhere(
          (box) =>
              box.constraints.maxWidth.isFinite &&
              box.constraints.maxWidth < narrowWidth + 1,
        );
    expect(bubbleBox.constraints.maxWidth, closeTo(narrowWidth * 0.96, 0.5));

    final tableScroll = find.descendant(
      of: find.byType(MarkdownHost),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      ),
    );
    expect(tableScroll, findsWidgets);

    final hostSize = tester.getSize(find.byType(MarkdownHost));
    expect(hostSize.width, lessThanOrEqualTo(narrowWidth));
  });
}
