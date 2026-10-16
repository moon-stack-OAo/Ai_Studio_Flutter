import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:desktop_fluent/pages/chat/widgets/message_bubble.dart';
import 'package:desktop_fluent/pages/chat/widgets/markdown_host.dart';
import 'package:desktop_fluent/pages/chat/widgets/streaming_text_body.dart';

void main() {
  testWidgets('Fluent 正反向跨块和块内部分复制不扩大选区', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final text =
        '${List.filled(4094, 'x').join()}\r\ne\u0301😀${List.filled(5000, '尾').join()}';
    await tester.pumpWidget(
      FluentApp(
        home: ScaffoldPage(
          content: SingleChildScrollView(
            child: StreamingTextBody(
              data: text,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final body = find.byType(StreamingTextBody);
    final paragraphs = tester
        .renderObjectList<RenderParagraph>(
          find.descendant(of: body, matching: find.byType(RichText)),
        )
        .toList();
    final delegate = tester
        .widget<SelectionContainer>(
          find
              .descendant(of: body, matching: find.byType(SelectionContainer))
              .first,
        )
        .delegate!;
    final region = tester.state<SelectableRegionState>(
      find.byType(SelectableRegion),
    );
    Offset position(int block, int offset) => paragraphs[block].localToGlobal(
      paragraphs[block].getOffsetForCaret(
            TextPosition(offset: offset),
            Rect.zero,
          ) +
          const Offset(0, 7),
    );
    for (final (startBlock, start, endBlock, end, expected) in [
      (0, 4090, 1, 4, 'xxxx\r\ne\u0301😀'),
      (1, 4, 0, 4090, 'xxxx\r\ne\u0301😀'),
      (0, 10, 0, 20, 'xxxxxxxxxx'),
      (1, 0, 1, 4, 'e\u0301😀'),
      (0, 4090, 0, 4094, 'xxxx'),
    ]) {
      region.clearSelection();
      delegate.dispatchSelectionEvent(
        SelectionEdgeUpdateEvent.forStart(
          globalPosition: position(startBlock, start),
        ),
      );
      // 与鼠标按下时一致：先在起点折叠选区，再拖动结束边界。
      delegate.dispatchSelectionEvent(
        SelectionEdgeUpdateEvent.forEnd(
          globalPosition: position(startBlock, start),
        ),
      );
      delegate.dispatchSelectionEvent(
        SelectionEdgeUpdateEvent.forEnd(
          globalPosition: position(endBlock, end),
        ),
      );
      await tester.pump();
      region.contextMenuButtonItems
          .firstWhere((item) => item.type == ContextMenuButtonType.copy)
          .onPressed
          ?.call();
      await tester.pump();
      expect(
        copied,
        expected,
        reason: '选区：块 $startBlock:$start → 块 $endBlock:$end',
      );
    }
  });

  for (final entry in <String, String>{
    '无换行长行': List.filled(10000, 'x').join(),
    'CRLF': List.filled(2000, '原文\r\n').join(),
    '块边界换行': '${List.filled(4095, 'x').join()}\n后续\n正文',
    '字素':
        '${List.filled(4095, 'x').join()}👨‍👩‍👧‍👦e\u0301😀${List.filled(5000, '尾').join()}',
  }.entries) {
    testWidgets('Fluent ${entry.key}跨块全选复制原文', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        FluentApp(
          home: ScaffoldPage(
            content: SingleChildScrollView(
              child: StreamingTextBody(
                data: entry.value,
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final region = tester.state<SelectableRegionState>(
        find.byType(SelectableRegion),
      );
      region.selectAll(SelectionChangedCause.keyboard);
      region.contextMenuButtonItems
          .firstWhere((item) => item.type == ContextMenuButtonType.copy)
          .onPressed
          ?.call();
      await tester.pump();
      expect(copied, entry.value);
    });
  }

  testWidgets('Fluent 自然换行分块不额外增加空白行', (tester) async {
    final text = List.filled(1000, 'line12345\n').join();
    const style = TextStyle(fontSize: 14, height: 1);
    await tester.pumpWidget(
      FluentApp(
        home: ScaffoldPage(
          content: SingleChildScrollView(
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 500,
                child: StreamingTextBody(data: text, style: style),
              ),
            ),
          ),
        ),
      ),
    );
    final paragraph = TextPainter(
      text: TextSpan(style: style, text: text),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 500);
    addTearDown(paragraph.dispose);
    expect(
      tester.getSize(find.byType(StreamingTextBody)).height,
      closeTo(paragraph.height, 0.01),
    );
  });

  testWidgets('Fluent 长正文选择区域允许触摸拖动外层列表', (tester) async {
    final scroll = ScrollController();
    await tester.pumpWidget(
      FluentApp(
        theme: buildFluentLightTheme(),
        home: ScaffoldPage(
          content: ListView(
            controller: scroll,
            reverse: true,
            children: [
              StreamingTextBody(
                data: List.filled(3000, '流式正文\n').join(),
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, 180));
    await tester.pump(const Duration(milliseconds: 64));
    expect(scroll.offset, greaterThan(100));
    await tester.pumpWidget(const SizedBox.shrink());
    scroll.dispose();
  });

  testWidgets('Fluent 长流式正文复用稳定前缀并保持选择，结束后使用 Markdown', (tester) async {
    final long =
        '${List.filled(600, '稳定行\n').join()}${List.filled(3000, '尾').join()}';
    Future<void> pump(String data, {bool streaming = true}) async {
      await tester.pumpWidget(
        FluentApp(
          theme: buildFluentLightTheme(),
          home: ScaffoldPage(
            content: SingleChildScrollView(
              child: MessageBubble(
                message: ChatMessage(
                  id: 'm',
                  createdAt: 1,
                  role: ChatRole.assistant,
                  content: data,
                  streaming: streaming,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await pump(long);
    final body = find.byType(StreamingTextBody);
    final texts = find.descendant(of: body, matching: find.byType(Text));
    final frozen = tester.widget<Text>(texts.first);
    expect(
      find.descendant(of: body, matching: find.byType(SelectionArea)),
      findsOneWidget,
    );
    await pump('$long新尾部');
    expect(identical(tester.widget(texts.first), frozen), isTrue);
    expect(tester.widget<Text>(texts.last).data, endsWith('新尾部'));
    await pump('**完成**\n\n$long新尾部', streaming: false);
    expect(find.byType(StreamingTextBody), findsNothing);
    expect(find.byType(MarkdownHost), findsOneWidget);
    expect(
      tester.widget<MarkdownHost>(find.byType(MarkdownHost)).data,
      endsWith('$long新尾部'),
    );
  });
}
