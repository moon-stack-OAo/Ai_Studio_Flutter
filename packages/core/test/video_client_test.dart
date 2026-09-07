import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;

Uint8List _testPng({int w = 1600, int h = 1200}) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(10, 20, 30));
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List _noisyJpg({int w = 2000, int h = 1500}) {
  final image = img.Image(width: w, height: h);
  for (var y = 0; y < h; y += 2) {
    for (var x = 0; x < w; x += 2) {
      final r = (x * 17 + y * 31) & 0xFF;
      final g = (x * 3) & 0xFF;
      final b = (y * 5) & 0xFF;
      image.setPixelRgb(x, y, r, g, b);
      if (x + 1 < w) image.setPixelRgb(x + 1, y, r, g, b);
      if (y + 1 < h) {
        image.setPixelRgb(x, y + 1, r, g, b);
        if (x + 1 < w) image.setPixelRgb(x + 1, y + 1, r, g, b);
      }
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

void main() {
  test('OpenAI createJob POST /videos 写 seconds+size', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, endsWith('/videos'));
      expect(request.headers['Authorization'], 'Bearer sk-test');
      expect(request.headers['x-api-key'], 'sk-test');
      final body = jsonDecode(request.body) as Map;
      expect(body['model'], 'sora-2');
      expect(body['prompt'], '一只猫跑步');
      expect(body['seconds'], '8');
      expect(body['size'], '1280x720');
      return http.Response(
        jsonEncode({
          'id': 'job_openai_1',
          'status': 'queued',
          'progress': 0,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final api = OpenAiCompatibleVideoClient(client: client);
    final job = await api.createJob(
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'sk-test',
      model: 'sora-2',
      prompt: '一只猫跑步',
      duration: 8,
      size: '1280x720',
      providerType: ProviderType.openai,
    );
    expect(job.jobId, 'job_openai_1');
    expect(job.status, VideoJobWireStatus.queued);
  });

  test('xAI createJob POST /videos/generations 写 duration+aspect_ratio+resolution',
      () async {
    Map? captured;
    final client = MockClient((request) async {
      expect(request.url.path, endsWith('/videos/generations'));
      captured = jsonDecode(request.body) as Map;
      return http.Response(
        jsonEncode({
          'request_id': 'req_xai_1',
          'status': 'pending',
        }),
        200,
      );
    });
    final api = OpenAiCompatibleVideoClient(client: client);
    final job = await api.createJob(
      baseUrl: 'https://api.x.ai/v1',
      apiKey: 'xai-k',
      model: 'grok-imagine-video',
      prompt: 'moon',
      duration: 5,
      aspectRatio: '16:9',
      resolution: '720p',
      providerType: ProviderType.xai,
    );
    expect(captured!['duration'], 5);
    expect(captured!['aspect_ratio'], '16:9');
    expect(captured!['resolution'], '720p');
    expect(captured!.containsKey('seconds'), isFalse);
    expect(job.jobId, 'req_xai_1');
  });

  test('Agnes createJob JSON body + require video_id', () async {
    Map? captured;
    Uri? uri;
    final client = MockClient((request) async {
      uri = request.url;
      captured = jsonDecode(request.body) as Map;
      return http.Response(
        jsonEncode({
          'video_id': 'vid_agnes_1',
          'status': 'queued',
        }),
        200,
      );
    });
    final api = OpenAiCompatibleVideoClient(client: client);
    final job = await api.createJob(
      baseUrl: 'https://api.agnes-ai.com/v1',
      apiKey: 'ag-k',
      model: 'agnes-video-2.5',
      prompt: 'cat runs',
      duration: 20,
      size: '1280x720',
      aspectRatio: '16:9',
      providerType: ProviderType.openaiCompatible,
    );
    expect(uri!.path, endsWith('/videos'));
    expect(captured!['mode'], 'text');
    expect(captured!['seconds'], '12');
    expect(captured!['size'], '720P');
    expect(captured!['aspect_ratio'], '16:9');
    expect(captured!['n'], 1);
    expect(job.jobId, 'vid_agnes_1');
  });

  test('Agnes img2video JSON mode=keyframe + first_frame dataUrl', () async {
    Map? captured;
    final client = MockClient((request) async {
      expect(request.headers['content-type'], contains('application/json'));
      captured = jsonDecode(request.body) as Map;
      return http.Response(
        jsonEncode({
          'video_id': 'vid_agnes_i2v',
          'status': 'queued',
        }),
        200,
      );
    });
    final api = OpenAiCompatibleVideoClient(client: client);
    final job = await api.createJob(
      baseUrl: 'https://api.agnes-ai.com/v1',
      apiKey: 'ag-k',
      model: 'agnes-video-2.5',
      prompt: '   ',
      mode: VideoGenMode.image,
      imageBytes: _testPng(w: 800, h: 600),
      imageFileName: 'ref.png',
      duration: 8,
      size: '960P',
      aspectRatio: '16:9',
      providerType: ProviderType.openaiCompatible,
    );
    expect(job.jobId, 'vid_agnes_i2v');
    expect(captured!['mode'], 'keyframe');
    expect(captured!['prompt'], '');
    expect(captured!['seconds'], '8');
    expect(captured!['size'], '960P');
    expect(captured!['n'], 1);
    expect(captured!['aspect_ratio'], '16:9');
    expect(captured!['first_frame'], startsWith('data:image/jpeg;base64,'));
    expect(captured!.containsKey('image'), isFalse);
    expect(captured!.containsKey('input_reference'), isFalse);
  });

  test('Agnes img2video HTTP 413 后激进压缩再重试', () async {
    var calls = 0;
    final frameLens = <int>[];
    final client = MockClient((request) async {
      calls += 1;
      final body = jsonDecode(request.body) as Map;
      final frame = body['first_frame'] as String;
      frameLens.add(frame.length);
      expect(body['mode'], 'keyframe');
      if (calls == 1) {
        return http.Response('payload too large', 413);
      }
      return http.Response(
        jsonEncode({'video_id': 'vid_retry', 'status': 'queued'}),
        200,
      );
    });
    final api = OpenAiCompatibleVideoClient(client: client);
    final job = await api.createJob(
      baseUrl: 'https://api.agnes-ai.com/v1',
      apiKey: 'ag-k',
      model: 'agnes-video-2.5',
      prompt: 'walk',
      mode: VideoGenMode.image,
      imageBytes: _noisyJpg(w: 2400, h: 1800),
      imageFileName: 'huge.png',
      providerType: ProviderType.openaiCompatible,
    );
    expect(calls, 2);
    expect(job.jobId, 'vid_retry');
    expect(frameLens[1], lessThan(frameLens[0]));
  });

  test('Agnes Flash size 强制 720P', () async {
    Map? captured;
    final client = MockClient((request) async {
      captured = jsonDecode(request.body) as Map;
      return http.Response(
        jsonEncode({'video_id': 'vf1', 'status': 'queued'}),
        200,
      );
    });
    final api = OpenAiCompatibleVideoClient(client: client);
    await api.createJob(
      baseUrl: 'https://hub.example.com/v1',
      apiKey: 'k',
      model: 'agnes-video-flash',
      prompt: 'x',
      duration: 8,
      size: '2K',
      providerType: ProviderType.openaiCompatible,
    );
    expect(captured!['size'], '720P');
  });

  test('Agnes getJob 走 agnesapi 且不拉 content', () async {
    Uri? pollUri;
    final client = MockClient((request) async {
      pollUri = request.url;
      expect(request.url.path.contains('/content'), isFalse);
      return http.Response(
        jsonEncode({
          'video_id': 'vid1',
          'status': 'completed',
          'url': 'https://cdn.example/a.mp4',
        }),
        200,
      );
    });
    final api = OpenAiCompatibleVideoClient(client: client);
    final job = await api.getJob(
      baseUrl: 'https://api.agnes-ai.com/v1',
      apiKey: 'k',
      jobId: 'vid1',
      videoModel: 'agnes-video-2.5',
      fetchContent: true,
    );
    expect(pollUri!.path, endsWith('/agnesapi'));
    expect(pollUri!.queryParameters['video_id'], 'vid1');
    expect(pollUri!.queryParameters['model_name'], 'agnes-video-2.5');
    expect(job.videoUrl, 'https://cdn.example/a.mp4');
  });

  test('agnes_profile helpers', () {
    expect(agnesVideoRatios, contains('21:9'));
    expect(agnesVideoRatios, contains('9:16'));
    expect(
      isAgnesProvider(baseUrl: 'https://api.agnes-ai.com/v1'),
      isTrue,
    );
    expect(isAgnesProvider(videoModel: 'agnes-video-2.5'), isTrue);
    expect(isAgnesProvider(baseUrl: 'https://api.openai.com'), isFalse);
    expect(isAgnesVideoFlash('agnes-video-flash'), isTrue);
    expect(normalizeAgnesVideoSize('960P'), '960P');
    expect(normalizeAgnesVideoSize('1920x1080'), '2K');
    expect(
      normalizeAgnesVideoSize('2K', videoModel: 'agnes-video-flash'),
      '720P',
    );
    expect(clampAgnesVideoSeconds(20), 12);
    expect(clampAgnesVideoSeconds(2), 4);
    expect(clampAgnesVideoSeconds(null), 5);
    final poll = buildAgnesPollUrl(
      baseUrl: 'https://api.agnes-ai.com/v1/',
      jobId: 'abc',
      videoModel: 'agnes-video-2.5',
    );
    expect(poll.toString(), contains('/agnesapi?'));
    expect(poll.queryParameters['video_id'], 'abc');
    expect(
      shouldFetchVideoContent(
        isXai: false,
        baseUrl: 'https://api.agnes-ai.com/v1',
        videoModel: 'agnes-video-2.5',
      ),
      isFalse,
    );
    expect(
      shouldFetchVideoContent(isXai: true),
      isFalse,
    );
    expect(
      shouldFetchVideoContent(
        isXai: false,
        baseUrl: 'https://api.openai.com/v1',
      ),
      isTrue,
    );
  });

  test('getJob 轮询 normalize + OpenAI content 落盘', () async {
    var poll = 0;
    final store = MemoryVideoAssetStore();
    final fakeMp4 = Uint8List.fromList([0, 0, 0, 0, 0x66, 0x74, 0x79, 0x70]);
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/content')) {
        expect(request.headers['Authorization'], 'Bearer sk');
        return http.Response.bytes(fakeMp4, 200);
      }
      poll++;
      if (poll == 1) {
        return http.Response(
          jsonEncode({'id': 'j1', 'status': 'in_progress', 'progress': 40}),
          200,
        );
      }
      return http.Response(
        jsonEncode({'id': 'j1', 'status': 'completed', 'progress': 100}),
        200,
      );
    });

    final api = OpenAiCompatibleVideoClient(
      client: client,
      pollInterval: const Duration(milliseconds: 10),
    );
    final first = await api.getJob(
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'sk',
      jobId: 'j1',
      fetchContent: false,
    );
    expect(first.status, VideoJobWireStatus.inProgress);
    expect(first.progress, 40);

    final done = await api.getJob(
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'sk',
      jobId: 'j1',
      assetStore: store,
      materializeId: 'item1',
    );
    expect(done.status, VideoJobWireStatus.completed);
    expect(done.localPath, startsWith('memory://'));
    expect(store.entries[done.localPath!], isNotNull);
  });

  test('waitJob 进度回调 + 可取消', () async {
    var n = 0;
    final client = MockClient((request) async {
      n++;
      if (n < 3) {
        return http.Response(
          jsonEncode({'id': 'w1', 'status': 'in_progress', 'progress': n * 10}),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'id': 'w1',
          'status': 'completed',
          'progress': 100,
          'url': 'https://cdn.example/v.mp4',
        }),
        200,
      );
    });
    final api = OpenAiCompatibleVideoClient(
      client: client,
      pollInterval: const Duration(milliseconds: 5),
    );
    final progresses = <double?>[];
    final job = await api.waitJob(
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'sk',
      jobId: 'w1',
      providerType: ProviderType.xai,
      fetchContent: false,
      onProgress: (j) => progresses.add(j.progress),
    );
    expect(job.status, VideoJobWireStatus.completed);
    expect(job.videoUrl, 'https://cdn.example/v.mp4');
    expect(progresses.length, greaterThanOrEqualTo(2));

    var cancelled = false;
    n = 0;
    await expectLater(
      api.waitJob(
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'sk',
        jobId: 'w1',
        providerType: ProviderType.xai,
        isCancelled: () => cancelled,
        onProgress: (_) {
          cancelled = true;
        },
      ),
      throwsA(isA<ChatAbortException>()),
    );
  });

  test('waitJob 可取消 sleep：取消后快速 Abort，不等满 pollInterval', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'id': 'w2',
          'status': 'in_progress',
          'progress': 10,
        }),
        200,
      );
    });
    final api = OpenAiCompatibleVideoClient(
      client: client,
      pollInterval: const Duration(seconds: 5),
    );
    var cancelled = false;
    final sw = Stopwatch()..start();
    final future = api.waitJob(
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'sk',
      jobId: 'w2',
      providerType: ProviderType.xai,
      fetchContent: false,
      interval: const Duration(seconds: 5),
      isCancelled: () => cancelled,
      onProgress: (_) {
        // 首轮 getJob 后进入 sleep，立刻取消应快速 Abort
        cancelled = true;
      },
    );
    await expectLater(future, throwsA(isA<ChatAbortException>()));
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(1500));
  });

  test('isPlayableVideoPath 拒绝 /content', () {
    expect(isPlayableVideoPath('https://cdn.example/v.mp4'), isTrue);
    expect(isPlayableVideoPath('memory://x'), isTrue);
    expect(isPlayableVideoPath(r'C:\tmp\a.mp4'), isTrue);
    expect(
      isPlayableVideoPath('https://api.example/v1/videos/x/content'),
      isFalse,
    );
    expect(isPlayableVideoPath('/videos/x/content'), isFalse);
    expect(isPlayableVideoPath(''), isFalse);
  });

  test('extractVideoJobIdFromContentUrl', () {
    expect(
      extractVideoJobIdFromContentUrl(
        'https://api.example.com/v1/videos/job_abc/content',
      ),
      'job_abc',
    );
    expect(extractVideoJobIdFromContentUrl('/videos/xyz/content'), 'xyz');
    expect(
      extractVideoJobIdFromContentUrl(
        'https://api.example.com/v1/videos/a%2Fb/content',
      ),
      'a/b',
    );
    expect(extractVideoJobIdFromContentUrl('https://cdn/a.mp4'), isNull);
  });

  test('materialize：/content 无 jobId 时仍鉴权下载', () async {
    final store = MemoryVideoAssetStore();
    final fakeMp4 = Uint8List.fromList([0, 0, 0, 0, 0x66, 0x74, 0x79, 0x70]);
    final client = MockClient((request) async {
      expect(request.url.path.endsWith('/content'), isTrue);
      expect(request.headers['Authorization'], 'Bearer sk');
      return http.Response.bytes(fakeMp4, 200);
    });
    final api = OpenAiCompatibleVideoClient(client: client);
    final out = await api.materialize(
      const VideoJob(
        jobId: '',
        status: VideoJobWireStatus.completed,
        videoUrl: 'https://api.example.com/v1/videos/job_r1/content',
      ),
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'sk',
      assetStore: store,
      materializeId: 'item_r1',
    );
    expect(out.needsMaterialize, isFalse);
    expect(out.jobId, 'job_r1');
    expect(out.localPath, startsWith('memory://'));
    expect(store.entries[out.localPath!], isNotNull);
  });

  test('materialize：/content 401 保留具体错误', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'error': {'message': 'invalid api key'},
        }),
        401,
      );
    });
    final api = OpenAiCompatibleVideoClient(client: client);
    final out = await api.materialize(
      const VideoJob(
        jobId: 'job_bad',
        status: VideoJobWireStatus.completed,
        videoUrl: 'https://api.example.com/v1/videos/job_bad/content',
      ),
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'sk-bad',
      assetStore: MemoryVideoAssetStore(),
    );
    expect(out.needsMaterialize, isTrue);
    expect(out.errorMessage, isNotNull);
    expect(
      out.errorMessage!,
      anyOf(contains('鉴权'), contains('invalid api key'), contains('401')),
    );
  });

  test('getJob：content 下载失败时 needsMaterialize + 具体错误', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/content')) {
        return http.Response('forbidden', 403);
      }
      return http.Response(
        jsonEncode({
          'id': 'job_c2',
          'status': 'completed',
          'progress': 100,
        }),
        200,
      );
    });
    final api = OpenAiCompatibleVideoClient(client: client);
    final out = await api.getJob(
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'sk',
      jobId: 'job_c2',
      assetStore: MemoryVideoAssetStore(),
      materializeId: 'item_c2',
    );
    expect(out.status, VideoJobWireStatus.completed);
    expect(out.needsMaterialize, isTrue);
    expect(out.errorMessage, isNotNull);
    expect(out.errorMessage!, isNot(contains('可尝试重新加载')));
    expect(out.remoteVideoUrl, contains('/videos/job_c2/content'));
  });

  test('normalizeVideoJob / extractVideoUrl', () {
    final j = normalizeVideoJob({
      'request_id': 'r1',
      'status': 'succeeded',
      'video': {'url': 'https://cdn.x.ai/a.mp4'},
      'progress': 100,
    });
    expect(j.jobId, 'r1');
    expect(j.status, VideoJobWireStatus.completed);
    expect(j.videoUrl, 'https://cdn.x.ai/a.mp4');

    expect(isDirectPlayableVideoUrl('https://cdn/a.mp4'), isTrue);
    expect(
      isDirectPlayableVideoUrl('https://api/v1/videos/x/content'),
      isFalse,
    );
    expect(isVideoContentPath('/v1/videos/abc/content'), isTrue);
  });

  test('img2video 允许空提示词', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, endsWith('/videos'));
      expect(request.headers['content-type'], contains('multipart/form-data'));
      captured = request;
      return http.Response(
        jsonEncode({
          'id': 'job_img2v_1',
          'status': 'queued',
          'progress': 0,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final api = OpenAiCompatibleVideoClient(client: client);
    final job = await api.createJob(
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'sk-test',
      model: 'sora-2',
      prompt: '   ',
      mode: VideoGenMode.image,
      imageBytes: _testPng(),
      imageFileName: 'ref.png',
      duration: 8,
      size: '1280x720',
      providerType: ProviderType.openai,
    );
    expect(job.jobId, 'job_img2v_1');
    final ascii = latin1.decode(captured.bodyBytes, allowInvalid: true);
    expect(ascii, contains('name="prompt"'));
    expect(ascii, contains('name="input_reference"'));
    expect(ascii, contains('filename="ref.jpg"'));
  });

  test('img2video 提交前压缩参考图', () async {
    int? uploadLen;
    final src = _noisyJpg(w: 2000, h: 1500);
    final client = MockClient((request) async {
      uploadLen = request.bodyBytes.length;
      return http.Response(
        jsonEncode({'id': 'job_c1', 'status': 'queued'}),
        200,
      );
    });
    final api = OpenAiCompatibleVideoClient(client: client);
    await api.createJob(
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'sk-test',
      model: 'sora-2',
      prompt: 'cat',
      mode: VideoGenMode.image,
      imageBytes: src,
      imageFileName: 'big.png',
      providerType: ProviderType.openai,
    );
    expect(uploadLen, isNotNull);
    expect(uploadLen!, lessThan(src.length + 4096));
  });

  test('img2video HTTP 413 后激进压缩再重试一次', () async {
    var calls = 0;
    final sizes = <int>[];
    final client = MockClient((request) async {
      calls += 1;
      sizes.add(request.bodyBytes.length);
      if (calls == 1) {
        return http.Response('payload too large', 413);
      }
      return http.Response(
        jsonEncode({'id': 'job_retry', 'status': 'queued'}),
        200,
      );
    });
    final api = OpenAiCompatibleVideoClient(client: client);
    final job = await api.createJob(
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'sk-test',
      model: 'sora-2',
      prompt: 'x',
      mode: VideoGenMode.image,
      imageBytes: _noisyJpg(w: 2400, h: 1800),
      imageFileName: 'huge.png',
      providerType: ProviderType.openai,
    );
    expect(calls, 2);
    expect(job.jobId, 'job_retry');
    expect(sizes[1], lessThan(sizes[0]));
  });

  test('img2video 413 重试仍失败抛出统一提示', () async {
    final client = MockClient((request) async {
      return http.Response('request entity too large', 413);
    });
    final api = OpenAiCompatibleVideoClient(client: client);
    await expectLater(
      api.createJob(
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'sk-test',
        model: 'sora-2',
        prompt: 'x',
        mode: VideoGenMode.image,
        imageBytes: _testPng(),
        providerType: ProviderType.openai,
      ),
      throwsA(
        isA<ChatApiException>()
            .having((e) => e.statusCode, 'status', 413)
            .having((e) => e.message, 'msg', contains('上传内容过大')),
      ),
    );
  });

  test('xAI img2video 413 同样重试且 body 为 jpeg dataUrl', () async {
    var calls = 0;
    String? dataUrl;
    final client = MockClient((request) async {
      calls += 1;
      final body = jsonDecode(request.body) as Map;
      dataUrl = (body['image'] as Map)['url'] as String;
      if (calls == 1) {
        return http.Response('HTTP 413', 413);
      }
      return http.Response(
        jsonEncode({'request_id': 'req_retry', 'status': 'pending'}),
        200,
      );
    });
    final api = OpenAiCompatibleVideoClient(client: client);
    final job = await api.createJob(
      baseUrl: 'https://api.x.ai/v1',
      apiKey: 'xai-k',
      model: 'grok-imagine-video',
      prompt: '',
      mode: VideoGenMode.image,
      imageBytes: _testPng(),
      providerType: ProviderType.xai,
    );
    expect(calls, 2);
    expect(job.jobId, 'req_retry');
    expect(dataUrl, startsWith('data:image/jpeg;base64,'));
  });

  test('txt2video 空提示词仍拒绝', () async {
    final api = OpenAiCompatibleVideoClient(
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    await expectLater(
      api.createJob(
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'sk-test',
        model: 'sora-2',
        prompt: '  ',
        mode: VideoGenMode.text,
      ),
      throwsA(
        isA<ChatApiException>().having(
          (e) => e.message,
          'msg',
          contains('提示词'),
        ),
      ),
    );
  });

  test('401 鉴权文案', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'error': {'message': 'bad key'},
        }),
        401,
      );
    });
    final api = OpenAiCompatibleVideoClient(client: client);
    await expectLater(
      api.createJob(
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'sk-bad',
        model: 'sora-2',
        prompt: 'x',
      ),
      throwsA(
        isA<ChatApiException>().having(
          (e) => e.message,
          'msg',
          anyOf(contains('鉴权'), contains('bad key')),
        ),
      ),
    );
  });

  test('ActiveVideoCredentials toString masks key', () {
    const creds = ActiveVideoCredentials(
      providerId: 'p',
      providerName: 'n',
      type: ProviderType.openai,
      baseUrl: 'https://api.openai.com/v1',
      apiKey: 'sk-should-not-leak',
      videoModel: 'sora-2',
    );
    expect(creds.toString().contains('sk-should-not-leak'), isFalse);
  });
}
