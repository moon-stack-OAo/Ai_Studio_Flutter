import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_material/pages/image/image_page.dart';
import 'package:mobile_material/pages/video/video_page.dart';

Future<ProviderRepository> _providers({bool load = true}) async {
  final repo = ProviderRepository(
    storage: MemoryProviderStorage(
      ProviderStoreSnapshot(
        providers: [
          ProviderConfig(
            id: 'p',
            name: 'Test',
            type: ProviderType.openaiCompatible,
            baseUrl: 'https://example.com/v1',
            apiKey: 'test-key',
            imageModel: 'dall-e-3',
            videoModel: 'sora-2',
            enabled: true,
          ),
        ],
        activeProviderId: 'p',
      ),
    ),
    connectionTester: StubProviderConnectionTester(),
  );
  if (load) await repo.load();
  return repo;
}

ImageSession _imageSession(String id, {bool empty = false}) => ImageSession(
  id: id,
  title: id,
  createdAt: 1,
  updatedAt: 1,
  items: empty
      ? []
      : [
          for (var i = 0; i < 45; i++)
            ImageItem(
              id: 'item-$i',
              createdAt: i + 1,
              mode: ImageGenMode.text,
              prompt: '$id prompt $i',
              images: [
                for (var j = 0; j < (i % 4) + 1; j++)
                  const ImageRef(type: ImageRefType.b64, src: ''),
              ],
            ),
        ],
);

VideoSession _videoSession(
  String id, {
  bool success = false,
  bool empty = false,
}) => VideoSession(
  id: id,
  title: id,
  createdAt: 1,
  updatedAt: 1,
  items: empty
      ? []
      : [
          for (var i = 0; i < 30; i++)
            VideoItem(
              id: 'item-$i',
              createdAt: i + 1,
              mode: VideoGenMode.text,
              prompt: '$id prompt $i',
              status: success ? VideoItemStatus.success : VideoItemStatus.error,
              errorMessage: success ? null : 'Test failure',
            ),
        ],
);

Future<void> _pumpPage(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(430, 850);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(theme: buildMaterialLightTheme(), home: page),
  );
  await tester.pumpAndSettle();
}

ScrollPosition _position(WidgetTester tester) => tester
    .widget<CustomScrollView>(find.byType(CustomScrollView).first)
    .controller!
    .position;

void main() {
  testWidgets('image opens long variable-height history at its actual bottom', (
    tester,
  ) async {
    final providers = await _providers();
    final repo = ImageSessionRepository(
      storage: MemoryImageSessionStorage(
        ImageStoreSnapshot(sessions: [_imageSession('a')], activeId: 'a'),
      ),
    );
    await repo.load();
    await _pumpPage(
      tester,
      ImagePage(
        providerRepository: providers,
        sessionRepository: repo,
        generation: GenerationRuntime(),
      ),
    );
    expect(_position(tester).extentAfter, lessThan(1));
  });

  testWidgets(
    'image switching equal-shaped histories resets to latest; empty chat shows composer',
    (tester) async {
      final providers = await _providers();
      final repo = ImageSessionRepository(
        storage: MemoryImageSessionStorage(
          ImageStoreSnapshot(
            sessions: [
              _imageSession('a'),
              _imageSession('b'),
              _imageSession('empty', empty: true),
            ],
            activeId: 'a',
          ),
        ),
      );
      await repo.load();
      await _pumpPage(
        tester,
        ImagePage(
          providerRepository: providers,
          sessionRepository: repo,
          generation: GenerationRuntime(),
        ),
      );
      _position(tester).jumpTo(300);
      await tester.pumpAndSettle();
      await repo.setActive('b');
      await tester.pumpAndSettle();
      expect(_position(tester).extentAfter, lessThan(1));
      await repo.setActive('empty');
      await tester.pumpAndSettle();
      expect(_position(tester).pixels, 0);
    },
  );

  testWidgets(
    'video switching equal-shaped histories resets to latest; empty chat shows composer',
    (tester) async {
      final providers = await _providers();
      final repo = VideoSessionRepository(
        storage: MemoryVideoSessionStorage(
          VideoStoreSnapshot(
            sessions: [
              _videoSession('a'),
              _videoSession('b'),
              _videoSession('empty', empty: true),
            ],
            activeId: 'a',
          ),
        ),
      );
      await repo.load();
      await _pumpPage(
        tester,
        VideoPage(
          providerRepository: providers,
          sessionRepository: repo,
          generation: GenerationRuntime(),
        ),
      );
      expect(_position(tester).extentAfter, lessThan(1));
      _position(tester).jumpTo(300);
      await tester.pumpAndSettle();
      await repo.setActive('b');
      await tester.pumpAndSettle();
      expect(_position(tester).extentAfter, lessThan(1));
      await repo.setActive('empty');
      await tester.pumpAndSettle();
      expect(_position(tester).pixels, 0);
    },
  );

  testWidgets(
    'video filter from previous session does not hide new-session tasks',
    (tester) async {
      final providers = await _providers();
      final repo = VideoSessionRepository(
        storage: MemoryVideoSessionStorage(
          VideoStoreSnapshot(
            sessions: [_videoSession('a'), _videoSession('b', success: true)],
            activeId: 'a',
          ),
        ),
      );
      await repo.load();
      await _pumpPage(
        tester,
        VideoPage(
          providerRepository: providers,
          sessionRepository: repo,
          generation: GenerationRuntime(),
        ),
      );
      final filter = find.widgetWithText(FilterChip, '失败');
      await tester.ensureVisible(filter);
      await tester.pumpAndSettle();
      await tester.tap(filter);
      await tester.pumpAndSettle();
      await repo.setActive('b');
      await tester.pumpAndSettle();
      expect(find.text('当前筛选无任务'), findsNothing);
    },
  );

  testWidgets(
    'image history reaches latest when provider loads after the page',
    (tester) async {
      final providers = await _providers(load: false);
      final repo = ImageSessionRepository(
        storage: MemoryImageSessionStorage(
          ImageStoreSnapshot(sessions: [_imageSession('a')], activeId: 'a'),
        ),
      );
      await repo.load();
      await _pumpPage(
        tester,
        ImagePage(
          providerRepository: providers,
          sessionRepository: repo,
          generation: GenerationRuntime(),
        ),
      );
      await providers.load();
      await tester.pumpAndSettle();
      expect(_position(tester).extentAfter, lessThan(1));
    },
  );

  testWidgets('dragging interrupts automatic image-history scrolling', (
    tester,
  ) async {
    final providers = await _providers();
    final repo = ImageSessionRepository(
      storage: MemoryImageSessionStorage(
        ImageStoreSnapshot(
          sessions: [_imageSession('a'), _imageSession('b')],
          activeId: 'a',
        ),
      ),
    );
    await repo.load();
    await _pumpPage(
      tester,
      ImagePage(
        providerRepository: providers,
        sessionRepository: repo,
        generation: GenerationRuntime(),
      ),
    );
    await repo.setActive('b');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CustomScrollView)),
    );
    await gesture.moveBy(const Offset(0, 100));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_position(tester).extentAfter, greaterThan(100));
  });
}
