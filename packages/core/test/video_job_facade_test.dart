import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late ProviderRepository providers;
  late VideoSessionRepository sessions;
  late GenerationRuntime generation;
  late MemoryVideoSessionStorage storage;
  late MemoryVideoAssetStore assets;

  setUp(() async {
    providers = ProviderRepository(
      storage: MemoryProviderStorage(),
      connectionTester: StubProviderConnectionTester(),
    );
    await providers.load();
    final added = await providers.addProvider(
      name: 'VideoTest',
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'sk-test',
      videoModel: 'sora-2',
    );
    await providers.setActiveProvider(added.id);

    storage = MemoryVideoSessionStorage();
    assets = MemoryVideoAssetStore();
    sessions = VideoSessionRepository(storage: storage, assetStore: assets);
    await sessions.load();
    generation = GenerationRuntime();
  });

  VideoJobFacade facadeWith(MockClient mock) {
    return VideoJobFacade(
      providers: providers,
      sessions: sessions,
      generation: generation,
      videoClient: OpenAiCompatibleVideoClient(
        client: mock,
        pollInterval: const Duration(milliseconds: 5),
        jobTimeout: const Duration(seconds: 2),
      ),
      createHttpClient: () => createSafeHttpClient(inner: mock),
    );
  }

  test('generate 成功路径：append → complete → generation 释放', () async {
    var n = 0;
    final mock = MockClient((request) async {
      n++;
      if (request.method == 'POST' && request.url.path.endsWith('/videos')) {
        return http.Response(
          jsonEncode({
            'id': 'job_ok',
            'status': 'queued',
            'progress': 0,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'id': 'job_ok',
          'status': 'completed',
          'progress': 100,
          'url': 'https://cdn.example/ok.mp4',
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final facade = facadeWith(mock);
    final notifies = <int>[];
    await facade.generate(
      prompt: '一只猫跑步',
      duration: 8,
      size: '1280x720',
      onNotify: () => notifies.add(1),
    );

    expect(generation.busy, isFalse);
    final item = sessions.activeSession!.items.last;
    expect(item.status, VideoItemStatus.success);
    expect(item.videoUrl, 'https://cdn.example/ok.mp4');
    expect(item.prompt, '一只猫跑步');
    expect(n, greaterThanOrEqualTo(2));
    expect(notifies, isNotEmpty);
    facade.dispose();
  });

  test('generate abort：stop 后 generation 释放且条目非 loading', () async {
    final mock = MockClient((request) async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return http.Response(
        jsonEncode({
          'id': 'job_abort',
          'status': 'queued',
          'progress': 0,
        }),
        200,
      );
    });

    final facade = facadeWith(mock);
    final future = facade.generate(
      prompt: 'abort me',
      onNotify: () {},
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(generation.busy, isTrue);
    facade.stop();
    await future;

    expect(generation.busy, isFalse);
    final item = sessions.activeSession!.items.last;
    expect(item.status, isNot(VideoItemStatus.loading));
    expect(
      item.status == VideoItemStatus.error ||
          item.status == VideoItemStatus.pendingResume,
      isTrue,
    );
    facade.dispose();
  });

  test('generate timeout → pending_resume + onInfo', () async {
    final mock = MockClient((request) async {
      if (request.method == 'POST') {
        return http.Response(
          jsonEncode({
            'id': 'job_to',
            'status': 'queued',
            'progress': 0,
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'id': 'job_to',
          'status': 'in_progress',
          'progress': 10,
        }),
        200,
      );
    });

    final facade = VideoJobFacade(
      providers: providers,
      sessions: sessions,
      generation: generation,
      videoClient: OpenAiCompatibleVideoClient(
        client: mock,
        pollInterval: const Duration(milliseconds: 5),
        jobTimeout: const Duration(milliseconds: 40),
      ),
      createHttpClient: () => createSafeHttpClient(inner: mock),
    );

    String? info;
    await facade.generate(
      prompt: 'timeout',
      onNotify: () {},
      onInfo: (m) => info = m,
    );

    expect(generation.busy, isFalse);
    final item = sessions.activeSession!.items.last;
    expect(item.status, VideoItemStatus.pendingResume);
    expect(item.needsResume, isTrue);
    expect(item.jobId, 'job_to');
    expect(info, isNotNull);
    facade.dispose();
  });

  test('resumePending 批处理占用 GenerationRuntime', () async {
    final sid = sessions.activeId;
    final item = await sessions.appendLoadingItem(
      sid,
      mode: VideoGenMode.text,
      prompt: 'resume',
      providerId: providers.activeProviderId,
    );
    await sessions.updateItem(
      sid,
      item!.id,
      status: VideoItemStatus.pendingResume,
      jobId: 'job_r',
      needsResume: true,
    );

    var n = 0;
    final mock = MockClient((request) async {
      n++;
      if (n == 1) {
        return http.Response(
          jsonEncode({
            'id': 'job_r',
            'status': 'in_progress',
            'progress': 40,
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'id': 'job_r',
          'status': 'completed',
          'progress': 100,
          'url': 'https://cdn.example/resumed.mp4',
        }),
        200,
      );
    });

    final facade = facadeWith(mock);
    final busyDuring = <bool>[];
    await facade.resumePending(
      onNotify: () {
        busyDuring.add(generation.busy);
      },
      onInfo: (_) {},
    );

    expect(generation.busy, isFalse);
    expect(busyDuring.any((b) => b), isTrue);
    final done = sessions.activeSession!.items.last;
    expect(done.status, VideoItemStatus.success);
    expect(done.videoUrl, 'https://cdn.example/resumed.mp4');
    facade.dispose();
  });

  test('abandonItem 委托仓库', () async {
    final sid = sessions.activeId;
    final item = await sessions.appendLoadingItem(
      sid,
      mode: VideoGenMode.text,
      prompt: 'x',
    );
    await sessions.updateItem(
      sid,
      item!.id,
      status: VideoItemStatus.pendingResume,
      jobId: 'j',
      needsResume: true,
    );

    final mock = MockClient((_) async => http.Response('{}', 500));
    final facade = VideoJobFacade(
      providers: providers,
      sessions: sessions,
      generation: generation,
      videoClient: OpenAiCompatibleVideoClient(client: mock),
      createHttpClient: () => createSafeHttpClient(inner: mock),
    );
    await facade.abandonItem(sid, item.id);
    expect(
      sessions.activeSession!.items.last.status,
      VideoItemStatus.abandoned,
    );
    facade.dispose();
  });

  group('Step2 参数 / 能力 / canGenerate', () {
    VideoJobFacade bareFacade() {
      return VideoJobFacade(
        providers: providers,
        sessions: sessions,
        generation: generation,
        videoClient: OpenAiCompatibleVideoClient(
          client: MockClient((_) async => http.Response('{}', 500)),
        ),
      );
    }

    test('canGenerate：空 prompt 无参考图为 false；有 prompt 为 true', () {
      final facade = bareFacade();
      expect(facade.canGenerate, isFalse);
      facade.setPromptDraft('hello');
      expect(facade.canGenerate, isTrue);
      facade.dispose();
    });

    test('canGenerate：仅参考图亦可生成', () {
      final facade = bareFacade();
      expect(facade.canGenerate, isFalse);
      facade.setHasReferenceImage(true);
      expect(facade.canGenerate, isTrue);
      facade.dispose();
    });

    test('默认能力：非 Agnes / 非 xAI', () {
      final facade = bareFacade();
      expect(facade.isAgnesActive, isFalse);
      expect(facade.isXaiVideoActive, isFalse);
      expect(facade.useAspectRatio, isFalse);
      expect(facade.useResolution, isFalse);
      expect(facade.showSize, isTrue);
      expect(facade.activeDurationOptions, VideoJobFacade.defaultDurationOptions);
      expect(facade.modelsCache, isA<ProviderModelsCache>());
      facade.dispose();
    });

    test('Agnes：能力探测 + syncParams 校正 duration/size', () async {
      final agnes = await providers.addProvider(
        name: 'Agnes',
        baseUrl: 'https://apihub.agnes-ai.com/v1',
        apiKey: 'sk-agnes',
        videoModel: 'agnes-video-2.5',
      );
      await providers.setActiveProvider(agnes.id);

      final facade = bareFacade();
      expect(facade.isAgnesActive, isTrue);
      expect(facade.useAspectRatio, isTrue);
      expect(facade.showSize, isTrue);
      expect(facade.activeDurationOptions, agnesVideoDurationOptions);
      expect(facade.activeAspectOptions, agnesVideoRatios);
      expect(facade.activeSizeOptions, agnesVideoSizes);

      facade.setDuration(10);
      facade.setSize('1280x720');
      var notified = false;
      facade.syncParamsToActiveProvider(onNotify: () => notified = true);

      expect(facade.duration, agnesVideoDurationDefault);
      expect(facade.size, '720P');
      expect(notified, isTrue);
      facade.dispose();
    });

    test('xAI：useAspectRatio + useResolution；sync 校正 resolution', () async {
      final xai = await providers.addProvider(
        name: 'xAI',
        baseUrl: 'https://api.x.ai/v1',
        apiKey: 'sk-xai',
        videoModel: 'grok-imagine-video',
        type: ProviderType.xai,
      );
      await providers.setActiveProvider(xai.id);

      final facade = bareFacade();
      expect(facade.isXaiVideoActive, isTrue);
      expect(facade.useAspectRatio, isTrue);
      expect(facade.useResolution, isTrue);
      expect(facade.showSize, isFalse);

      facade.setResolution('999p');
      var notified = false;
      facade.syncParamsToActiveProvider(onNotify: () => notified = true);
      expect(facade.resolution, '720p');
      expect(notified, isTrue);
      facade.dispose();
    });

    test('syncParams 无变化时不回调 onNotify', () {
      final facade = bareFacade();
      var notified = false;
      facade.syncParamsToActiveProvider(onNotify: () => notified = true);
      expect(notified, isFalse);
      facade.dispose();
    });
  });

  group('Step3 reloadVideo / resolveVideoBytes', () {
    test('reloadVideo 直链 https：completeItem + onInfo', () async {
      final sid = sessions.activeId;
      final item = await sessions.appendLoadingItem(
        sid,
        mode: VideoGenMode.text,
        prompt: 'reload-direct',
        providerId: providers.activeProviderId,
      );
      await sessions.completeItem(
        sid,
        item!.id,
        videoUrl: 'https://cdn.example.com/a.mp4',
        remoteVideoUrl: 'https://cdn.example.com/a.mp4',
        needsMaterialize: false,
      );
      final live = sessions.activeSession!.items.last;

      final mock = MockClient((_) async => http.Response('{}', 500));
      final facade = facadeWith(mock);
      String? info;
      String? banner;
      await facade.reloadVideo(
        live,
        onNotify: () {},
        onBanner: (m) => banner = m,
        onInfo: (m) => info = m,
      );

      expect(banner, isNull);
      expect(info, '视频已重新加载');
      expect(facade.isReloading(live.id), isFalse);
      expect(generation.busy, isFalse);
      final done = sessions.activeSession!.items.last;
      expect(done.status, VideoItemStatus.success);
      expect(done.videoUrl, 'https://cdn.example.com/a.mp4');
      expect(done.needsMaterialize, isFalse);
      facade.dispose();
    });

    test('reloadVideo 鉴权 /content 成功落盘', () async {
      final sid = sessions.activeId;
      final item = await sessions.appendLoadingItem(
        sid,
        mode: VideoGenMode.text,
        prompt: 'reload-auth',
        providerId: providers.activeProviderId,
      );
      await sessions.updateItem(
        sid,
        item!.id,
        status: VideoItemStatus.error,
        jobId: 'job_reload',
        remoteVideoUrl: 'https://api.example.com/v1/videos/job_reload/content',
        needsMaterialize: true,
        errorMessage: '需重新加载',
      );
      final live = sessions.activeSession!.items.last;
      final fakeMp4 =
          Uint8List.fromList([0, 0, 0, 0, 0x66, 0x74, 0x79, 0x70]);

      final mock = MockClient((request) async {
        expect(request.url.path, contains('/content'));
        return http.Response.bytes(fakeMp4, 200);
      });
      final facade = facadeWith(mock);
      String? info;
      await facade.reloadVideo(
        live,
        onNotify: () {},
        onInfo: (m) => info = m,
      );

      expect(info, '视频已重新加载');
      expect(facade.isReloading(live.id), isFalse);
      expect(generation.busy, isFalse);
      final done = sessions.activeSession!.items.last;
      expect(done.status, VideoItemStatus.success);
      expect(done.needsMaterialize, isFalse);
      expect(done.localPath, startsWith('memory://'));
      final bytes = await facade.resolveVideoBytes(done);
      expect(bytes, isNotNull);
      expect(bytes!.length, fakeMp4.length);
      facade.dispose();
    });

    test('reloadVideo 失败 → markNeedsMaterialize + onBanner', () async {
      final sid = sessions.activeId;
      final item = await sessions.appendLoadingItem(
        sid,
        mode: VideoGenMode.text,
        prompt: 'reload-fail',
        providerId: providers.activeProviderId,
      );
      await sessions.updateItem(
        sid,
        item!.id,
        status: VideoItemStatus.error,
        jobId: 'job_fail',
        remoteVideoUrl: 'https://api.example.com/v1/videos/job_fail/content',
        needsMaterialize: true,
      );
      final live = sessions.activeSession!.items.last;

      final mock = MockClient((_) async => http.Response('boom', 500));
      final facade = facadeWith(mock);
      String? banner;
      await facade.reloadVideo(
        live,
        onNotify: () {},
        onBanner: (m) => banner = m,
      );

      expect(banner, isNotNull);
      expect(facade.isReloading(live.id), isFalse);
      expect(generation.busy, isFalse);
      final done = sessions.activeSession!.items.last;
      expect(done.needsMaterialize, isTrue);
      facade.dispose();
    });

    test('reloadVideo busy 时拒绝；同 id 并发忽略第二次', () async {
      final sid = sessions.activeId;
      final item = await sessions.appendLoadingItem(
        sid,
        mode: VideoGenMode.text,
        prompt: 'reload-busy',
        providerId: providers.activeProviderId,
      );
      await sessions.updateItem(
        sid,
        item!.id,
        status: VideoItemStatus.error,
        jobId: 'job_busy',
        remoteVideoUrl: 'https://api.example.com/v1/videos/job_busy/content',
        needsMaterialize: true,
      );
      final live = sessions.activeSession!.items.last;

      var hits = 0;
      final mock = MockClient((_) async {
        hits++;
        await Future<void>.delayed(const Duration(milliseconds: 80));
        return http.Response.bytes(
          Uint8List.fromList([1, 2, 3, 4]),
          200,
        );
      });
      final facade = facadeWith(mock);

      // busy：占用 generation
      final token = generation.begin(sid, () {});
      String? rejected;
      await facade.reloadVideo(
        live,
        onNotify: () {},
        onBanner: (m) => rejected = m,
      );
      expect(rejected, '当前有任务进行中，请稍后再试');
      expect(hits, 0);
      generation.end(sid, token);

      // 并发：第二次同 id 应被忽略
      hits = 0;
      final first = facade.reloadVideo(live, onNotify: () {});
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(facade.isReloading(live.id), isTrue);
      await facade.reloadVideo(live, onNotify: () {});
      await first;
      expect(hits, 1);
      expect(facade.isReloading(live.id), isFalse);
      facade.dispose();
    });

    test('resolveVideoBytes：assetStore memory://', () async {
      final path = await assets.saveMp4(
        Uint8List.fromList([9, 8, 7]),
        'bytes_item',
      );
      final mock = MockClient((_) async => http.Response('{}', 500));
      final facade = facadeWith(mock);
      final item = VideoItem(
        id: 'bytes_item',
        createdAt: 1,
        mode: VideoGenMode.text,
        prompt: 'x',
        status: VideoItemStatus.success,
        localPath: path,
        videoUrl: path,
      );
      final bytes = await facade.resolveVideoBytes(item);
      expect(bytes, [9, 8, 7]);
      facade.dispose();
    });
  });
}
