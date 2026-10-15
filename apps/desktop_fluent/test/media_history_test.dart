import 'package:core/core.dart';
import 'package:desktop_fluent/pages/image/widgets/image_timeline.dart';
import 'package:desktop_fluent/pages/video/widgets/video_queue.dart';
import 'package:desktop_fluent/widgets/collapsible_prompt.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    FluentApp(
      theme: buildFluentLightTheme(),
      home: ScaffoldPage(content: child),
    ),
  );
  await tester.pumpAndSettle();
}

ImageTimeline _imageTimeline(String sessionId) => ImageTimeline(
  key: ValueKey(sessionId),
  items: [
    for (var i = 0; i < 40; i++)
      ImageItem(
        id: 'image-$i',
        createdAt: i + 1,
        mode: ImageGenMode.text,
        prompt: i == 39 ? 'latest-image-prompt' : 'older-image-$i',
        images: const [ImageRef(type: ImageRefType.b64, src: '')],
      ),
  ],
  loadBytes: (_) async => null,
  onPreview: (_, _, _) {},
  onSave: (_, _, _) {},
);

VideoQueue _videoQueue(String sessionId, {bool success = false}) => VideoQueue(
  key: ValueKey(sessionId),
  items: [
    for (var i = 0; i < 30; i++)
      VideoItem(
        id: 'video-$i',
        createdAt: i + 1,
        mode: VideoGenMode.text,
        prompt: i == 29 ? 'latest-video-prompt' : 'older-video-$i',
        status: success ? VideoItemStatus.success : VideoItemStatus.error,
        errorMessage: success ? null : 'Test failure',
      ),
  ],
  onOpen: (_) {},
  onSave: (_) {},
  onResume: (_) {},
  onAbandon: (_) {},
);

void main() {
  testWidgets('desktop image keeps latest first across long histories', (
    tester,
  ) async {
    await _pump(tester, _imageTimeline('a'));
    expect(find.text('latest-image-prompt').hitTestable(), findsOneWidget);
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    position.jumpTo(800);
    await tester.pumpAndSettle();
    await _pump(tester, _imageTimeline('b'));
    expect(find.text('latest-image-prompt').hitTestable(), findsOneWidget);
  });

  testWidgets(
    'desktop video keeps latest first and clears previous session filter',
    (tester) async {
      await _pump(tester, _videoQueue('a'));
      // 正文和任务标题都会显示短提示词，这里只验证用户回合正文。
      final latestPrompt = find.descendant(
        of: find.byWidgetPredicate(
          (widget) =>
              widget is CollapsiblePrompt &&
              widget.text == 'latest-video-prompt',
        ),
        matching: find.text('latest-video-prompt'),
      );
      expect(latestPrompt.hitTestable(), findsOneWidget);
      await tester.tap(find.text('失败').first);
      await tester.pumpAndSettle();
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      position.jumpTo(800);
      await tester.pumpAndSettle();
      expect(latestPrompt.hitTestable(), findsNothing);
      await _pump(tester, _videoQueue('b', success: true));
      expect(find.text('当前筛选无任务'), findsNothing);
      expect(latestPrompt.hitTestable(), findsOneWidget);
      expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .pixels,
        0,
      );
    },
  );
}
