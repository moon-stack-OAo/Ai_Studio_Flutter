import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late ProviderRepository providers;
  late ImageSessionRepository sessions;
  late GenerationRuntime generation;

  setUp(() async {
    providers = ProviderRepository(
      storage: MemoryProviderStorage(),
      connectionTester: StubProviderConnectionTester(),
    );
    await providers.load();
    final added = await providers.addProvider(
      name: 'ImageTest',
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'sk-test',
      imageModel: 'gpt-image-1',
    );
    await providers.setActiveProvider(added.id);

    sessions = ImageSessionRepository(
      storage: MemoryImageSessionStorage(),
      assetStore: MemoryImageAssetStore(),
    );
    await sessions.load();
    generation = GenerationRuntime();
  });

  ImageSessionFacade facadeWith(MockClient mock) {
    return ImageSessionFacade(
      providers: providers,
      sessions: sessions,
      generation: generation,
      imageClient: OpenAiCompatibleImageClient(client: mock),
      createHttpClient: () => createSafeHttpClient(inner: mock),
    );
  }

  test('generate 成功路径：append → complete → generation 释放', () async {
    final mock = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, endsWith('/images/generations'));
      final body = jsonDecode(request.body) as Map;
      expect(body['prompt'], '一只猫');
      expect(body['n'], 2);
      expect(body['size'], '1024x1024');
      return http.Response(
        jsonEncode({
          'data': [
            {'b64_json': 'YWJj'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final facade = facadeWith(mock);
    facade.setN(2);
    facade.setPromptDraft('一只猫');
    final notifies = <int>[];
    await facade.generate(
      onNotify: () => notifies.add(1),
    );

    expect(generation.busy, isFalse);
    expect(facade.promptDraft, isEmpty);
    final item = sessions.activeSession!.items.last;
    expect(item.status, ImageItemStatus.done);
    expect(item.prompt, '一只猫');
    expect(item.n, 2);
    expect(item.images, isNotEmpty);
    expect(notifies, isNotEmpty);
    facade.dispose();
  });

  test('stop 调用 abort 的 cancelFn', () {
    final facade = ImageSessionFacade(
      providers: providers,
      sessions: sessions,
      generation: generation,
    );
    var cancelled = false;
    generation.begin(sessions.activeId, () => cancelled = true);
    expect(generation.busy, isTrue);
    facade.stop();
    expect(cancelled, isTrue);
    // abort 只触发 cancelFn，不清理 busy（由 generate finally → end）
    expect(generation.busy, isTrue);
    facade.dispose();
  });

  test('generate abort-like：ClientException closed → 已取消', () async {
    final mock = MockClient((request) async {
      throw http.ClientException('Client is closed');
    });

    final facade = facadeWith(mock);
    await facade.generate(
      prompt: 'abort me',
      onNotify: () {},
    );

    expect(generation.busy, isFalse);
    final item = sessions.activeSession!.items.last;
    expect(item.status, ImageItemStatus.error);
    expect(item.errorMessage, '已取消');
    facade.dispose();
  });

  test('busy 门闩：其它会话占用时 generate 直接返回', () async {
    final mock = MockClient((request) async {
      fail('不应发请求');
    });
    final facade = facadeWith(mock);
    generation.begin('other-busy', () {});

    await facade.generate(
      prompt: 'blocked',
      onNotify: () {},
    );

    expect(sessions.activeSession?.items ?? const [], isEmpty);
    facade.dispose();
  });

  test('canGenerate / 参数 setters', () {
    final facade = ImageSessionFacade(
      providers: providers,
      sessions: sessions,
      generation: generation,
    );

    expect(facade.canGenerate, isFalse);
    facade.setPromptDraft('hello');
    expect(facade.promptDraft, 'hello');
    expect(facade.canGenerate, isTrue);

    facade.setN(9);
    expect(facade.n, 4);
    facade.setSize('1024x1792');
    expect(facade.size, '1024x1792');
    facade.setAspectRatio('16:9');
    expect(facade.aspectRatio, '16:9');
    facade.setQuality('high');
    expect(facade.quality, 'high');

    generation.begin('busy', () {});
    expect(facade.canGenerate, isFalse);

    facade.dispose();
  });

  test('bannerOnGenerateError：错误时回调 onBanner', () async {
    final mock = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'error': {'message': 'upstream boom'},
        }),
        500,
      );
    });

    final facade = facadeWith(mock);
    String? banner;
    await facade.generate(
      prompt: 'fail',
      onNotify: () {},
      onBanner: (m) => banner = m,
      bannerOnGenerateError: true,
    );

    expect(generation.busy, isFalse);
    expect(banner, isNotNull);
    expect(banner, contains('upstream boom'));
    final item = sessions.activeSession!.items.last;
    expect(item.status, ImageItemStatus.error);
    facade.dispose();
  });

  test('图生：传入 imageBytes 走 edits', () async {
    var hitEdits = false;
    final mock = MockClient((request) async {
      if (request.url.path.endsWith('/images/edits')) {
        hitEdits = true;
        return http.Response(
          jsonEncode({
            'data': [
              {'b64_json': 'ZWRpdA=='},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      fail('应走 edits 而非 generations');
    });

    final facade = facadeWith(mock);
    await facade.generate(
      prompt: 'edit me',
      imageBytes: Uint8List.fromList([1, 2, 3, 4]),
      imageFileName: 'ref.png',
      onNotify: () {},
    );

    expect(hitEdits, isTrue);
    final item = sessions.activeSession!.items.last;
    expect(item.mode, ImageGenMode.edit);
    expect(item.status, ImageItemStatus.done);
    facade.dispose();
  });
}
