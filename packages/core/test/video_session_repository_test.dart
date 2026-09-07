import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late VideoSessionRepository repo;
  late MemoryVideoSessionStorage storage;
  late MemoryVideoAssetStore assets;

  setUp(() async {
    storage = MemoryVideoSessionStorage();
    assets = MemoryVideoAssetStore();
    repo = VideoSessionRepository(storage: storage, assetStore: assets);
    await repo.load();
  });

  test('load 空存储创建默认会话', () {
    expect(repo.sessions.length, 1);
    expect(repo.activeId, isNotEmpty);
    expect(repo.activeSession?.title, '新视频');
  });

  test('create / setActive / remove', () async {
    final a = repo.activeSession!;
    final b = await repo.createSession(title: '第二');
    expect(repo.activeId, b.id);
    expect(repo.sessions.length, 2);

    await repo.setActive(a.id);
    expect(repo.activeId, a.id);

    await repo.removeSession(b.id);
    expect(repo.sessions.any((s) => s.id == b.id), isFalse);
    expect(repo.sessions, isNotEmpty);
  });

  test('appendLoading 截 title + complete', () async {
    final sid = repo.activeId;
    final item = await repo.appendLoadingItem(
      sid,
      mode: VideoGenMode.text,
      prompt: '这是一段超过二十四字的生视频提示词用来截断标题测试啊',
      model: 'sora-2',
      providerName: 'OpenAI',
      duration: 8,
    );
    expect(item, isNotNull);
    expect(repo.activeSession!.title.length, 24);
    expect(item!.status, VideoItemStatus.loading);

    await repo.completeItem(
      sid,
      item.id,
      videoUrl: 'https://cdn.example/v.mp4',
      remoteVideoUrl: 'https://cdn.example/v.mp4',
    );
    final done = repo.activeSession!.items.last;
    expect(done.status, VideoItemStatus.success);
    expect(done.videoUrl, 'https://cdn.example/v.mp4');
  });

  test('hydrate：loading+jobId → pending_resume；无 jobId → error', () async {
    final dirty = VideoSession(
      id: 'vid_dirty',
      title: '脏',
      createdAt: 1,
      updatedAt: 2,
      items: [
        const VideoItem(
          id: 'v1',
          createdAt: 1,
          mode: VideoGenMode.text,
          prompt: 'a',
          status: VideoItemStatus.loading,
          jobId: 'job_keep',
        ),
        const VideoItem(
          id: 'v2',
          createdAt: 2,
          mode: VideoGenMode.text,
          prompt: 'b',
          status: VideoItemStatus.loading,
        ),
      ],
    );
    await storage.save(
      VideoStoreSnapshot(sessions: [dirty], activeId: dirty.id),
    );
    final b = VideoSessionRepository(storage: storage, assetStore: assets);
    await b.load();
    expect(b.activeSession!.items[0].status, VideoItemStatus.pendingResume);
    expect(b.activeSession!.items[0].needsResume, isTrue);
    expect(b.activeSession!.items[0].jobId, 'job_keep');
    expect(b.activeSession!.items[1].status, VideoItemStatus.error);
    expect(b.activeSession!.items[1].errorMessage, '上次异常中断');
  });

  test('abandonItem', () async {
    final sid = repo.activeId;
    final item = await repo.appendLoadingItem(
      sid,
      mode: VideoGenMode.text,
      prompt: 'x',
    );
    await repo.updateItem(
      sid,
      item!.id,
      status: VideoItemStatus.pendingResume,
      jobId: 'j',
      needsResume: true,
    );
    await repo.abandonItem(sid, item.id);
    expect(
      repo.activeSession!.items.last.status,
      VideoItemStatus.abandoned,
    );
    expect(repo.activeSession!.items.last.needsResume, isFalse);
  });

  test('resumePendingJobs 成功续完', () async {
    final sid = repo.activeId;
    final item = await repo.appendLoadingItem(
      sid,
      mode: VideoGenMode.text,
      prompt: 'resume me',
      providerId: 'p1',
    );
    await repo.updateItem(
      sid,
      item!.id,
      status: VideoItemStatus.pendingResume,
      jobId: 'job_r1',
      needsResume: true,
    );

    var n = 0;
    final client = OpenAiCompatibleVideoClient(
      client: MockClient((request) async {
        n++;
        if (n == 1) {
          return http.Response(
            jsonEncode({
              'id': 'job_r1',
              'status': 'in_progress',
              'progress': 50,
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'id': 'job_r1',
            'status': 'completed',
            'progress': 100,
            'url': 'https://cdn.example/done.mp4',
          }),
          200,
        );
      }),
      pollInterval: const Duration(milliseconds: 5),
    );

    final provider = ProviderConfig(
      id: 'p1',
      name: 'Test',
      type: ProviderType.xai,
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'sk',
      videoModel: 'grok-imagine-video',
    );

    final results = await resumePendingJobs(
      repository: repo,
      client: client,
      resolveProvider: (_) => provider,
      interval: const Duration(milliseconds: 5),
    );
    expect(results.length, 1);
    expect(results.first.error, isNull);
    final done = repo.activeSession!.items.last;
    expect(done.status, VideoItemStatus.success);
    expect(done.videoUrl, 'https://cdn.example/done.mp4');
    expect(done.needsResume, isFalse);
  });

  test('resumePendingJobs abort → 回 pending_resume', () async {
    final sid = repo.activeId;
    final item = await repo.appendLoadingItem(
      sid,
      mode: VideoGenMode.text,
      prompt: 'abort',
      providerId: 'p1',
    );
    await repo.updateItem(
      sid,
      item!.id,
      status: VideoItemStatus.pendingResume,
      jobId: 'job_a1',
      needsResume: true,
    );

    var cancelled = false;
    final client = OpenAiCompatibleVideoClient(
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'id': 'job_a1',
            'status': 'in_progress',
            'progress': 10,
          }),
          200,
        );
      }),
      pollInterval: const Duration(milliseconds: 5),
    );

    final provider = ProviderConfig(
      id: 'p1',
      name: 'Test',
      type: ProviderType.openai,
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'sk',
      videoModel: 'sora-2',
    );

    final future = resumePendingJobs(
      repository: repo,
      client: client,
      resolveProvider: (_) => provider,
      interval: const Duration(milliseconds: 5),
      isCancelled: () => cancelled,
      onProgress: (_, __, ___) {
        cancelled = true;
      },
    );
    final results = await future;
    expect(results, isNotEmpty);
    final live = repo.activeSession!.items.last;
    expect(live.status, VideoItemStatus.pendingResume);
    expect(live.needsResume, isTrue);
  });

  test('updateItem 相同 URL 不重复写、同 progress 可短路', () async {
    final sid = repo.activeId;
    final item = await repo.appendLoadingItem(
      sid,
      mode: VideoGenMode.text,
      prompt: 'dedupe',
    );
    await repo.updateItem(
      sid,
      item!.id,
      status: VideoItemStatus.loading,
      progress: 40,
      videoUrl: 'https://cdn.example/early.mp4',
      remoteVideoUrl: 'https://cdn.example/early.mp4',
      jobId: 'job_d1',
    );
    final afterFirst = repo.activeSession!.items.last;
    expect(afterFirst.videoUrl, 'https://cdn.example/early.mp4');
    expect(afterFirst.progress, 40);

    await repo.updateItem(
      sid,
      item.id,
      status: VideoItemStatus.loading,
      progress: 40,
      videoUrl: 'https://cdn.example/early.mp4',
      remoteVideoUrl: 'https://cdn.example/early.mp4',
      jobId: 'job_d1',
    );
    final afterSame = repo.activeSession!.items.last;
    expect(identical(afterFirst, afterSame), isTrue);

    await repo.updateItem(
      sid,
      item.id,
      status: VideoItemStatus.loading,
      progress: 55,
      videoUrl: 'https://cdn.example/early.mp4',
      remoteVideoUrl: 'https://cdn.example/early.mp4',
      jobId: 'job_d1',
    );
    final afterProgress = repo.activeSession!.items.last;
    expect(afterProgress.progress, 55);
    expect(afterProgress.videoUrl, 'https://cdn.example/early.mp4');
  });

  test('Memory 持久化 roundtrip', () async {
    final sid = repo.activeId;
    final item = await repo.appendLoadingItem(
      sid,
      mode: VideoGenMode.text,
      prompt: '持久化',
      duration: 4,
    );
    await repo.completeItem(
      sid,
      item!.id,
      videoUrl: 'https://example.com/a.mp4',
    );

    final b = VideoSessionRepository(storage: storage, assetStore: assets);
    await b.load();
    expect(b.activeId, sid);
    expect(b.activeSession!.items.length, 1);
    expect(b.activeSession!.items.first.prompt, '持久化');
    expect(b.activeSession!.items.first.status, VideoItemStatus.success);
  });

  test('needsMaterialize 序列化 + markNeedsMaterialize', () async {
    final sid = repo.activeId;
    final item = await repo.appendLoadingItem(
      sid,
      mode: VideoGenMode.text,
      prompt: 'mat',
    );
    await repo.markNeedsMaterialize(
      sid,
      item!.id,
      remoteVideoUrl: 'https://api.example/v1/videos/j1/content',
      jobId: 'j1',
    );
    final live = repo.activeSession!.items.last;
    expect(live.status, VideoItemStatus.error);
    expect(live.needsMaterialize, isTrue);
    expect(live.jobId, 'j1');
    expect(live.remoteVideoUrl, contains('/content'));

    final b = VideoSessionRepository(storage: storage, assetStore: assets);
    await b.load();
    final again = b.activeSession!.items.last;
    expect(again.needsMaterialize, isTrue);
    expect(again.jobId, 'j1');
  });

  test('resumePendingJobs：仅 /content 不可 complete', () async {
    final sid = repo.activeId;
    final item = await repo.appendLoadingItem(
      sid,
      mode: VideoGenMode.text,
      prompt: 'content only',
      providerId: 'p1',
    );
    await repo.updateItem(
      sid,
      item!.id,
      status: VideoItemStatus.pendingResume,
      jobId: 'job_c1',
      needsResume: true,
    );

    // completed 但只有 /content：materialize 鉴权下载失败 → needsMaterialize
    final client = OpenAiCompatibleVideoClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/content')) {
          return http.Response('<html>unauthorized</html>', 401);
        }
        return http.Response(
          jsonEncode({
            'id': 'job_c1',
            'status': 'completed',
            'progress': 100,
            'url': 'https://api.example.com/v1/videos/job_c1/content',
          }),
          200,
        );
      }),
      pollInterval: const Duration(milliseconds: 5),
    );

    final provider = ProviderConfig(
      id: 'p1',
      name: 'Test',
      type: ProviderType.xai,
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'sk',
      videoModel: 'grok-imagine-video',
    );

    final results = await resumePendingJobs(
      repository: repo,
      client: client,
      resolveProvider: (_) => provider,
      interval: const Duration(milliseconds: 5),
    );
    expect(results.length, 1);
    expect(results.first.error, isNull);
    final done = repo.activeSession!.items.last;
    expect(done.status, VideoItemStatus.error);
    expect(done.needsMaterialize, isTrue);
    expect(done.needsResume, isFalse);
  });
}
