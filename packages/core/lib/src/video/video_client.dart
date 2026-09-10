import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../chat/chat_errors.dart';
import '../logging/app_log_entry.dart';
import '../logging/app_log_level.dart';
import '../logging/app_log_repository.dart';
import '../openai/openai_urls.dart';
import '../provider/agnes_profile.dart';
import '../provider/provider_repository.dart';
import '../provider/provider_type.dart';
import '../provider/xai_profile.dart';
import '../security/safe_http_client.dart';
import '../security/url_safety.dart';
import '../util/image_compress.dart';
import 'video_asset_store.dart';
import 'video_models.dart';

/// 默认轮询间隔。
const Duration defaultVideoPollInterval = Duration(seconds: 5);

/// 默认总超时（30 分钟）。
const Duration defaultVideoJobTimeout = Duration(minutes: 30);

/// 单次 HTTP 超时。
const Duration defaultVideoHttpTimeout = Duration(seconds: 120);

/// 下载视频超时。
const Duration defaultVideoDownloadTimeout = Duration(minutes: 5);

/// 视频任务超时（可恢复）。
class VideoJobTimeoutException implements Exception {
  const VideoJobTimeoutException([
    this.message = '视频生成超时，可稍后在会话中恢复轮询',
  ]);

  final String message;

  @override
  String toString() => message;
}

/// OpenAI / xAI 兼容生视频客户端。
class OpenAiCompatibleVideoClient {
  OpenAiCompatibleVideoClient({
    http.Client? client,
    this.httpTimeout = defaultVideoHttpTimeout,
    this.pollInterval = defaultVideoPollInterval,
    this.jobTimeout = defaultVideoJobTimeout,
    this.downloadTimeout = defaultVideoDownloadTimeout,
    this.logs,
  })  : _ownedClient = client == null,
        _client = client ?? createSafeHttpClient();

  final http.Client _client;
  final bool _ownedClient;
  final Duration httpTimeout;
  final Duration pollInterval;
  final Duration jobTimeout;
  final Duration downloadTimeout;
  final AppLogRepository? logs;

  bool get ownsClient => _ownedClient;

  void close() {
    if (_ownedClient) {
      _client.close();
    }
  }

  Future<VideoJob> createJobWithCredentials(
    ActiveVideoCredentials credentials, {
    required String prompt,
    VideoGenMode mode = VideoGenMode.text,
    Uint8List? imageBytes,
    String imageFileName = 'image.png',
    int? duration,
    String? size,
    String? aspectRatio,
    String? resolution,
    Duration? timeout,
    http.Client? client,
  }) {
    return createJob(
      baseUrl: credentials.baseUrl,
      apiKey: credentials.apiKey,
      model: credentials.videoModel,
      providerType: credentials.type,
      prompt: prompt,
      mode: mode,
      imageBytes: imageBytes,
      imageFileName: imageFileName,
      duration: duration,
      size: size,
      aspectRatio: aspectRatio,
      resolution: resolution,
      timeout: timeout,
      client: client,
    );
  }

  /// 创建任务：OpenAI `POST /videos`；xAI `POST /videos/generations`。
  /// 图生参考图会先压缩；若 HTTP 413 则更激进压缩后重试一次。
  Future<VideoJob> createJob({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String prompt,
    ProviderType providerType = ProviderType.openaiCompatible,
    VideoGenMode mode = VideoGenMode.text,
    Uint8List? imageBytes,
    String imageFileName = 'image.png',
    int? duration,
    String? size,
    String? aspectRatio,
    String? resolution,
    Duration? timeout,
    http.Client? client,
  }) async {
    final modelId = model.trim();
    if (modelId.isEmpty) {
      throw const ChatApiException('请先设置视频模型');
    }
    if (normalizeBaseUrl(baseUrl).isEmpty) {
      throw const ChatApiException('请先填写 Base URL');
    }
    try {
      assertSafeBaseUrl(baseUrl);
    } on UrlSafetyException catch (e) {
      throw ChatApiException(e.message);
    }
    final text = prompt.trim();
    if (text.isEmpty && mode != VideoGenMode.image) {
      throw const ChatApiException('请输入提示词');
    }
    if (mode == VideoGenMode.image &&
        (imageBytes == null || imageBytes.isEmpty)) {
      throw const ChatApiException('图生视频需要上传参考图');
    }

    final isXai = isXaiVideoProvider(
      providerType: providerType,
      baseUrl: baseUrl,
      videoModel: modelId,
    );
    final agnes = isAgnesVideoProvider(baseUrl: baseUrl, videoModel: modelId);
    final effectiveClient = client ?? _client;
    final reqTimeout = timeout ?? httpTimeout;

    Future<VideoJob> once({required bool aggressive}) {
      return _createJobOnce(
        baseUrl: baseUrl,
        apiKey: apiKey,
        modelId: modelId,
        text: text,
        mode: mode,
        imageBytes: imageBytes,
        imageFileName: imageFileName,
        duration: duration,
        size: size,
        aspectRatio: aspectRatio,
        resolution: resolution,
        isXai: isXai,
        agnes: agnes,
        aggressiveCompress: aggressive,
        timeout: reqTimeout,
        client: effectiveClient,
      );
    }

    try {
      return await once(aggressive: false);
    } catch (error) {
      if (isAbortLike(error)) rethrow;
      final canRetry = mode == VideoGenMode.image &&
          imageBytes != null &&
          imageBytes.isNotEmpty &&
          isHttp413Error(error);
      if (!canRetry) {
        if (isHttp413Error(error)) {
          throw const ChatApiException(http413Hint, statusCode: 413);
        }
        rethrow;
      }
      try {
        return await once(aggressive: true);
      } catch (retryErr) {
        if (isAbortLike(retryErr)) rethrow;
        if (isHttp413Error(retryErr)) {
          throw const ChatApiException(http413Hint, statusCode: 413);
        }
        rethrow;
      }
    }
  }

  Future<VideoJob> _createJobOnce({
    required String baseUrl,
    required String apiKey,
    required String modelId,
    required String text,
    required VideoGenMode mode,
    required Uint8List? imageBytes,
    required String imageFileName,
    required int? duration,
    required String? size,
    required String? aspectRatio,
    required String? resolution,
    required bool isXai,
    required bool agnes,
    required bool aggressiveCompress,
    required Duration timeout,
    required http.Client client,
  }) async {
    CompressedImage? compressed;
    if (mode == VideoGenMode.image &&
        imageBytes != null &&
        imageBytes.isNotEmpty) {
      try {
        compressed = compressImageBytes(
          imageBytes,
          options: aggressiveCompress
              ? ImageCompressOptions.videoAggressive
              : ImageCompressOptions.videoDefault,
          fileName: imageFileName,
        );
      } catch (e) {
        throw ChatApiException(
          e is StateError ? e.message : '图片压缩失败',
        );
      }
    }

    if (isXai) {
      final body = <String, dynamic>{
        'model': modelId.isEmpty ? 'grok-imagine-video' : modelId,
        'prompt': text,
      };
      if (duration != null) body['duration'] = duration;
      final ar = aspectRatio?.trim();
      if (ar != null && ar.isNotEmpty) body['aspect_ratio'] = ar;
      final res = resolution?.trim();
      if (res != null && res.isNotEmpty) body['resolution'] = res;
      if (compressed != null) {
        body['image'] = {'url': compressed.dataUrl};
      }
      final data = await _postJson(
        uri: videoGenerationsUri(baseUrl),
        apiKey: apiKey,
        body: body,
        timeout: timeout,
        client: client,
      );
      var job = normalizeVideoJob(data);
      if (job.jobId.isEmpty) {
        throw const ChatApiException('未返回 request_id');
      }
      // 中转常在创建响应里写 status=success/completed 却无 video.url；
      // 无直链时一律按排队处理，避免跳过轮询。
      if (job.status != VideoJobWireStatus.failed &&
          (job.videoUrl == null || job.videoUrl!.trim().isEmpty)) {
        job = job.copyWith(status: VideoJobWireStatus.queued);
      }
      return job;
    }

    // Agnes：JSON POST /videos；v2.0 与 2.5/Flash 请求体不同。
    if (agnes) {
      final Map<String, dynamic> body;
      if (isAgnesVideoV20(modelId)) {
        final dims = resolveAgnesV20Dimensions(aspectRatio);
        body = <String, dynamic>{
          'model': modelId,
          'prompt': text,
          'width': dims.width,
          'height': dims.height,
          'num_frames': agnesV20NumFramesForSeconds(duration),
          'frame_rate': 24,
        };
        if (mode == VideoGenMode.image && compressed != null) {
          body['image'] = compressed.dataUrl;
        }
      } else {
        // 2.5 / Flash：seconds + size + aspect_ratio；图生 keyframe
        body = <String, dynamic>{
          'model': modelId,
          'prompt': text,
          'seconds': '${clampAgnesVideoSeconds(duration)}',
          'size': normalizeAgnesVideoSize(size, videoModel: modelId),
          'n': 1,
        };
        final ar = aspectRatio?.trim();
        if (ar != null && ar.isNotEmpty) body['aspect_ratio'] = ar;
        if (mode == VideoGenMode.image && compressed != null) {
          body['mode'] = 'keyframe';
          body['first_frame'] = compressed.dataUrl;
        } else {
          body['mode'] = 'text';
        }
      }
      final data = await _postJson(
        uri: videosUri(baseUrl),
        apiKey: apiKey,
        body: body,
        timeout: timeout,
        client: client,
      );
      final job = normalizeVideoJob(data);
      if (job.jobId.isEmpty) {
        throw const ChatApiException('未返回 video_id');
      }
      return job;
    }

    // OpenAI / 兼容
    if (mode == VideoGenMode.image && compressed != null) {
      final uri = videosUri(baseUrl);
      final headers = authHeaders(apiKey);
      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll(headers)
        ..fields['model'] = modelId
        ..fields['prompt'] = text
        ..files.add(
          http.MultipartFile.fromBytes(
            'input_reference',
            compressed.bytes,
            filename: compressed.fileName,
          ),
        );
      if (duration != null) {
        request.fields['seconds'] = '$duration';
      }
      final sz = size?.trim();
      if (sz != null && sz.isNotEmpty) request.fields['size'] = sz;

      late http.StreamedResponse streamed;
      try {
        streamed = await client.send(request).timeout(timeout);
      } on TimeoutException {
        throw const ChatApiException('请求超时，请稍后重试或增大超时时间');
      } catch (e) {
        if (isAbortLike(e)) throw toAbortError();
        throw ChatApiException(describeNetworkError(e));
      }
      final raw = await _readBody(streamed);
      final data = _decodeJsonBody(streamed.statusCode, raw);
      return normalizeVideoJob(data);
    }

    final body = <String, dynamic>{
      'model': modelId,
      'prompt': text,
    };
    if (duration != null) body['seconds'] = '$duration';
    final sz = size?.trim();
    if (sz != null && sz.isNotEmpty) body['size'] = sz;

    final data = await _postJson(
      uri: videosUri(baseUrl),
      apiKey: apiKey,
      body: body,
      timeout: timeout,
      client: client,
    );
    return normalizeVideoJob(data);
  }

  /// 查询任务：`GET /videos/{id}`；Agnes 用 agnesapi；OpenAI 完成无 URL 时可拉 content。
  Future<VideoJob> getJob({
    required String baseUrl,
    required String apiKey,
    required String jobId,
    ProviderType providerType = ProviderType.openaiCompatible,
    String? videoModel,
    bool fetchContent = true,
    VideoAssetStore? assetStore,
    String? materializeId,
    Duration? timeout,
    http.Client? client,
  }) async {
    final id = jobId.trim();
    if (id.isEmpty) throw const ChatApiException('缺少任务 ID');
    if (normalizeBaseUrl(baseUrl).isEmpty) {
      throw const ChatApiException('请先填写 Base URL');
    }

    final isXai = isXaiVideoProvider(
      providerType: providerType,
      baseUrl: baseUrl,
      videoModel: videoModel,
    );
    final agnes = isAgnesVideoProvider(baseUrl: baseUrl, videoModel: videoModel);
    final effectiveClient = client ?? _client;
    final reqTimeout = timeout ?? httpTimeout;
    final headers = authHeaders(
      apiKey,
      extra: {'Accept': 'application/json'},
    );

    final pollUri = agnes
        ? buildAgnesPollUrl(
            baseUrl: baseUrl,
            jobId: id,
            videoModel: videoModel,
          )
        : videoJobUri(baseUrl, id);

    late http.Response response;
    try {
      response = await effectiveClient
          .get(pollUri, headers: headers)
          .timeout(reqTimeout);
    } on TimeoutException {
      throw const ChatApiException('请求超时，请稍后重试或增大超时时间');
    } catch (e) {
      if (isAbortLike(e)) throw toAbortError();
      throw ChatApiException(describeNetworkError(e));
    }

    final data = _decodeJsonBody(response.statusCode, response.body);
    var job = normalizeVideoJob(data, fallbackId: id);

    final allowContent = fetchContent &&
        shouldFetchVideoContent(
          isXai: isXai,
          providerType: providerType,
          baseUrl: baseUrl,
          videoModel: videoModel,
        );

    if (allowContent &&
        job.status == VideoJobWireStatus.completed &&
        (job.videoUrl == null || job.videoUrl!.isEmpty)) {
      final contentRemote = videoContentUri(baseUrl, id).toString();
      try {
        final path = await downloadContent(
          baseUrl: baseUrl,
          apiKey: apiKey,
          jobId: id,
          assetStore: assetStore,
          materializeId: materializeId ?? id,
          client: effectiveClient,
        );
        job = job.copyWith(
          videoUrl: path,
          localPath: path,
          remoteVideoUrl: contentRemote,
          needsMaterialize: false,
          clearErrorMessage: true,
        );
      } catch (e) {
        if (isAbortLike(e)) rethrow;
        job = job.copyWith(
          remoteVideoUrl: contentRemote,
          needsMaterialize: true,
          errorMessage: toChatErrorMessage(e, '下载视频内容失败'),
        );
      }
    }

    if (job.status == VideoJobWireStatus.completed &&
        job.videoUrl != null &&
        job.videoUrl!.isNotEmpty) {
      job = await materialize(
        job,
        baseUrl: baseUrl,
        apiKey: apiKey,
        providerType: providerType,
        assetStore: assetStore,
        materializeId: materializeId ?? id,
        client: effectiveClient,
      );
    }

    // 完成态仍无可播文件：补齐 needsMaterialize + 可读错误，避免落到笼统默认文案
    if (job.status == VideoJobWireStatus.completed &&
        resolvePlayableVideoPath(job).isEmpty) {
      final remote = (job.remoteVideoUrl ?? '').trim().isNotEmpty
          ? job.remoteVideoUrl
          : (allowContent ? videoContentUri(baseUrl, id).toString() : null);
      job = job.copyWith(
        remoteVideoUrl: remote,
        needsMaterialize: true,
        errorMessage: (job.errorMessage?.trim().isNotEmpty == true)
            ? job.errorMessage
            : (allowContent
                ? '视频已生成但下载失败，可尝试重新加载'
                : '视频已生成但未返回可播放地址'),
      );
    }

    return job;
  }

  /// 轮询直至完成 / 失败；可取消；默认间隔 5s、总超时 30min。
  Future<VideoJob> waitJob({
    required String baseUrl,
    required String apiKey,
    required String jobId,
    ProviderType providerType = ProviderType.openaiCompatible,
    String? videoModel,
    bool fetchContent = true,
    VideoAssetStore? assetStore,
    String? materializeId,
    Duration? interval,
    Duration? timeout,
    void Function(VideoJob job)? onProgress,
    bool Function()? isCancelled,
    http.Client? client,
  }) async {
    // 显式传入的 interval 尊重调用方（测试可用更短）；默认仍不低于 1s
    final rawInterval = interval ?? pollInterval;
    final intervalMs = interval != null
        ? rawInterval.inMilliseconds.clamp(1, 1 << 30)
        : rawInterval.inMilliseconds.clamp(1000, 1 << 30);
    final limit = timeout ?? jobTimeout;
    final startedAt = DateTime.now();
    var round = 0;

    while (true) {
      if (isCancelled?.call() == true) throw toAbortError();
      if (limit > Duration.zero &&
          DateTime.now().difference(startedAt) >= limit) {
        throw const VideoJobTimeoutException();
      }

      final job = await getJob(
        baseUrl: baseUrl,
        apiKey: apiKey,
        jobId: jobId,
        providerType: providerType,
        videoModel: videoModel,
        fetchContent: fetchContent,
        assetStore: assetStore,
        materializeId: materializeId,
        client: client,
      );
      round += 1;
      _logPollRound(round: round, job: job);
      onProgress?.call(job);
      if (job.status == VideoJobWireStatus.failed) return job;
      if (job.status == VideoJobWireStatus.completed) {
        final hasUrl = resolvePlayableVideoPath(job).isNotEmpty ||
            (job.videoUrl?.trim().isNotEmpty ?? false);
        if (hasUrl) return job;
        // 已尝试 content / 确认无直链：结束；否则继续等晚到的 URL
        if (job.needsMaterialize) return job;
      }

      // 可取消 sleep：取消后立刻 Abort，无需等满一轮 interval
      await cancellableSleep(
        Duration(milliseconds: intervalMs),
        isCancelled: isCancelled,
      );
    }
  }

  /// 可取消延迟，对齐现网 `sleep(ms, signal)`。
  static Future<void> cancellableSleep(
    Duration duration, {
    bool Function()? isCancelled,
  }) async {
    if (isCancelled?.call() == true) throw toAbortError();
    if (duration <= Duration.zero) return;

    final completer = Completer<void>();
    final timer = Timer(duration, () {
      if (!completer.isCompleted) completer.complete();
    });
    Timer? watcher;
    if (isCancelled != null) {
      watcher = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (isCancelled()) {
          timer.cancel();
          watcher?.cancel();
          if (!completer.isCompleted) {
            completer.completeError(toAbortError());
          }
        }
      });
    }
    try {
      await completer.future;
    } finally {
      timer.cancel();
      watcher?.cancel();
    }
  }

  /// 创建并等待完成。
  Future<VideoJob> generate({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String prompt,
    ProviderType providerType = ProviderType.openaiCompatible,
    VideoGenMode mode = VideoGenMode.text,
    Uint8List? imageBytes,
    String imageFileName = 'image.png',
    int? duration,
    String? size,
    String? aspectRatio,
    String? resolution,
    VideoAssetStore? assetStore,
    String? materializeId,
    Duration? interval,
    Duration? timeout,
    void Function(VideoJob job)? onProgress,
    bool Function()? isCancelled,
    http.Client? client,
  }) async {
    final created = await createJob(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      prompt: prompt,
      providerType: providerType,
      mode: mode,
      imageBytes: imageBytes,
      imageFileName: imageFileName,
      duration: duration,
      size: size,
      aspectRatio: aspectRatio,
      resolution: resolution,
      client: client,
    );
    onProgress?.call(created);
    final skipContent = !shouldFetchVideoContent(
      isXai: isXaiVideoProvider(
        providerType: providerType,
        baseUrl: baseUrl,
        videoModel: model,
      ),
      providerType: providerType,
      baseUrl: baseUrl,
      videoModel: model,
    );
    if (created.status.isTerminal) {
      // 完成态但无 URL：无论是否 xAI，只要有 jobId 就继续轮询
      // （中转创建响应常误标 completed/success）。
      if (created.status == VideoJobWireStatus.completed &&
          (created.videoUrl == null || created.videoUrl!.isEmpty) &&
          created.jobId.isNotEmpty) {
        return waitJob(
          baseUrl: baseUrl,
          apiKey: apiKey,
          jobId: created.jobId,
          providerType: providerType,
          videoModel: model,
          assetStore: assetStore,
          materializeId: materializeId,
          interval: interval,
          timeout: timeout,
          onProgress: onProgress,
          isCancelled: isCancelled,
          client: client,
        );
      }
      if (created.status == VideoJobWireStatus.completed &&
          (created.videoUrl?.trim().isNotEmpty ?? false)) {
        return materialize(
          created,
          baseUrl: baseUrl,
          apiKey: apiKey,
          providerType: providerType,
          assetStore: assetStore,
          materializeId: materializeId ?? created.jobId,
          client: client,
        );
      }
      if (created.status == VideoJobWireStatus.completed &&
          resolvePlayableVideoPath(created).isEmpty) {
        return created.copyWith(
          needsMaterialize: true,
          errorMessage: (created.errorMessage?.trim().isNotEmpty == true)
              ? created.errorMessage
              : (created.jobId.isEmpty
                  ? '未返回任务 ID 与视频地址'
                  : (skipContent
                      ? '视频已生成但未返回可播放地址'
                      : '视频已生成但下载失败，可尝试重新加载')),
        );
      }
      return created;
    }
    if (created.jobId.isEmpty) {
      throw const ChatApiException('未返回任务 ID');
    }
    return waitJob(
      baseUrl: baseUrl,
      apiKey: apiKey,
      jobId: created.jobId,
      providerType: providerType,
      videoModel: model,
      assetStore: assetStore,
      materializeId: materializeId,
      interval: interval,
      timeout: timeout,
      onProgress: onProgress,
      isCancelled: isCancelled,
      client: client,
    );
  }

  /// 有 https 直链则保留；OpenAI `/content` 鉴权下载到 [assetStore]。
  Future<VideoJob> materialize(
    VideoJob job, {
    required String baseUrl,
    required String apiKey,
    ProviderType providerType = ProviderType.openaiCompatible,
    VideoAssetStore? assetStore,
    String? materializeId,
    http.Client? client,
  }) async {
    if (job.status != VideoJobWireStatus.completed) return job;
    var src = (job.videoUrl ?? '').trim();
    if (src.isEmpty) {
      return job.copyWith(
        needsMaterialize: true,
        errorMessage: job.errorMessage ?? '未返回视频地址，请重新生成',
      );
    }
    if (src.startsWith('memory://') ||
        src.startsWith('file:') ||
        (!src.startsWith('http') && src.contains(RegExp(r'[/\\]')))) {
      return job.copyWith(localPath: src, needsMaterialize: false);
    }

    if (isVideoContentPath(src) || src.startsWith('/')) {
      src = resolveVideoContentUrl(src, baseUrl);
    }

    if (isDirectPlayableVideoUrl(src)) {
      return job.copyWith(
        videoUrl: src,
        remoteVideoUrl: src,
        needsMaterialize: false,
        clearErrorMessage: true,
      );
    }

    // 需鉴权 content 或其它 http
    if (RegExp(r'^https?://', caseSensitive: false).hasMatch(src)) {
      try {
        if (isVideoContentPath(src)) {
          final contentJobId = job.jobId.trim().isNotEmpty
              ? job.jobId.trim()
              : (extractVideoJobIdFromContentUrl(src) ?? '');
          if (contentJobId.isEmpty) {
            return job.copyWith(
              videoUrl: src,
              remoteVideoUrl: job.remoteVideoUrl ?? src,
              needsMaterialize: true,
              errorMessage: '缺少任务 ID，无法鉴权下载视频',
            );
          }
          // 优先用已解析的绝对 content URL（避免 baseUrl 与远端不一致）
          final bytes =
              await _downloadBytes(src, apiKey: apiKey, client: client);
          final store = assetStore ?? MemoryVideoAssetStore();
          final path =
              await store.saveMp4(bytes, materializeId ?? contentJobId);
          return job.copyWith(
            jobId: contentJobId,
            videoUrl: path,
            localPath: path,
            remoteVideoUrl: src,
            needsMaterialize: false,
            clearErrorMessage: true,
          );
        }
        // 非 /content 的 http：尽量带鉴权（部分中转也要求 header）
        final bytes =
            await _downloadBytes(src, apiKey: apiKey, client: client);
        if (assetStore != null) {
          final path = await assetStore.saveMp4(
            bytes,
            materializeId ?? job.jobId,
          );
          return job.copyWith(
            videoUrl: path,
            localPath: path,
            remoteVideoUrl: isDirectPlayableVideoUrl(src)
                ? src
                : (job.remoteVideoUrl ?? src),
            needsMaterialize: false,
            clearErrorMessage: true,
          );
        }
        return job.copyWith(
          videoUrl: src,
          remoteVideoUrl: src,
          needsMaterialize: true,
          errorMessage: '无本地存储，无法缓存视频文件',
        );
      } catch (e) {
        if (isAbortLike(e)) rethrow;
        return job.copyWith(
          videoUrl: src,
          remoteVideoUrl: job.remoteVideoUrl ?? src,
          needsMaterialize: true,
          errorMessage: toChatErrorMessage(e, '视频已生成但本地加载失败'),
        );
      }
    }

    return job.copyWith(
      errorMessage: job.errorMessage ?? '无法解析视频地址: $src',
      needsMaterialize: true,
    );
  }

  /// 鉴权下载 `/videos/{id}/content` 到本地。
  Future<String> downloadContent({
    required String baseUrl,
    required String apiKey,
    required String jobId,
    VideoAssetStore? assetStore,
    String? materializeId,
    http.Client? client,
  }) async {
    final bytes = await _downloadBytes(
      videoContentUri(baseUrl, jobId).toString(),
      apiKey: apiKey,
      client: client,
    );
    final store = assetStore ?? MemoryVideoAssetStore();
    return store.saveMp4(bytes, materializeId ?? jobId);
  }

  Future<Uint8List> _downloadBytes(
    String url, {
    required String apiKey,
    http.Client? client,
  }) async {
    try {
      assertSafeFetchUrl(url);
    } on UrlSafetyException catch (e) {
      throw ChatApiException(e.message);
    }
    final effectiveClient = client ?? _client;
    final headers = authHeaders(apiKey);
    late http.Response response;
    try {
      response = await effectiveClient
          .get(Uri.parse(url), headers: headers)
          .timeout(downloadTimeout);
    } on TimeoutException {
      throw const ChatApiException('下载视频超时');
    } catch (e) {
      if (isAbortLike(e)) throw toAbortError();
      throw ChatApiException(describeNetworkError(e));
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String bodyMsg = '';
      try {
        final decoded = jsonDecode(response.body);
        bodyMsg = extractApiErrorMessage(decoded);
      } catch (_) {
        bodyMsg = response.body.trim();
        if (bodyMsg.length > 300) bodyMsg = bodyMsg.substring(0, 300);
      }
      final msg = httpStatusErrorMessage(response.statusCode, bodyMsg);
      final cleaned = sanitizeErrorText(msg, '');
      throw ChatApiException(
        cleaned.isNotEmpty ? cleaned : 'HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
    final bytes = response.bodyBytes;
    if (bytes.isEmpty) {
      throw const ChatApiException('视频内容为空');
    }
    final head = String.fromCharCodes(
      bytes.take(16).toList(),
    ).trimLeft();
    if (head.startsWith('<') || head.toLowerCase().startsWith('<!doctype')) {
      throw const ChatApiException('下载到的不是视频文件');
    }
    return bytes;
  }

  Future<Object?> _postJson({
    required Uri uri,
    required String apiKey,
    required Map<String, dynamic> body,
    required Duration timeout,
    required http.Client client,
  }) async {
    final headers = authHeaders(
      apiKey,
      extra: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    );
    late http.Response response;
    try {
      response = await client
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(timeout);
    } on TimeoutException {
      throw const ChatApiException('请求超时，请稍后重试或增大超时时间');
    } catch (e) {
      if (isAbortLike(e)) throw toAbortError();
      throw ChatApiException(describeNetworkError(e));
    }
    return _decodeJsonBody(response.statusCode, response.body);
  }

  void _logPollRound({required int round, required VideoJob job}) {
    final logs = this.logs;
    if (logs == null) return;
    final level = switch (job.status) {
      VideoJobWireStatus.failed => AppLogLevel.error,
      VideoJobWireStatus.completed =>
        (resolvePlayableVideoPath(job).isEmpty &&
                (job.videoUrl == null || job.videoUrl!.trim().isEmpty))
            ? AppLogLevel.warn
            : AppLogLevel.info,
      _ => AppLogLevel.info,
    };
    unawaited(
      logs.append(
        level: level,
        source: AppLogSources.video,
        message: formatVideoPollLog(round: round, job: job),
      ),
    );
  }

  Future<String> _readBody(http.StreamedResponse streamed) async {
    try {
      return await streamed.stream.bytesToString();
    } catch (e) {
      if (isAbortLike(e)) throw toAbortError();
      return '';
    }
  }

  Object? _decodeJsonBody(int statusCode, String raw) {
    if (statusCode < 200 || statusCode >= 300) {
      String bodyMsg = '';
      try {
        final decoded = jsonDecode(raw);
        bodyMsg = extractApiErrorMessage(decoded);
      } catch (_) {
        bodyMsg = raw.trim();
        if (bodyMsg.length > 300) bodyMsg = bodyMsg.substring(0, 300);
      }
      final msg = httpStatusErrorMessage(statusCode, bodyMsg);
      final cleaned = sanitizeErrorText(msg, '');
      throw ChatApiException(
        cleaned.isNotEmpty ? cleaned : 'HTTP $statusCode',
        statusCode: statusCode,
      );
    }
    try {
      return jsonDecode(raw);
    } catch (_) {
      throw const ChatApiException('响应解析失败');
    }
  }
}

String extractVideoJobId(Object? data) {
  if (data is! Map) return '';
  final m = Map<String, dynamic>.from(data);
  // 部分中转再包一层 data
  final root = m['data'] is Map && m['data'] is! List
      ? Map<String, dynamic>.from(m['data'] as Map)
      : m;
  for (final key in [
    'video_id',
    'videoId',
    'request_id',
    'requestId',
    'job_id',
    'jobId',
    'task_id',
    'taskId',
    'id',
  ]) {
    final v = root[key] ?? m[key];
    if (v != null && v.toString().trim().isNotEmpty) {
      return v.toString().trim();
    }
  }
  return '';
}

bool isDirectPlayableVideoUrl(String? url) {
  final s = (url ?? '').trim();
  if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(s)) {
    return false;
  }
  if (RegExp(r'/videos/[^/]+/content/?$', caseSensitive: false).hasMatch(s) ||
      RegExp(r'/v1/videos/[^/]+/content/?$', caseSensitive: false)
          .hasMatch(s)) {
    return false;
  }
  return true;
}

/// 真正可播：本地/memory 路径，或非 `/content` 的 https 直链。
bool isPlayableVideoPath(String? path) {
  final s = (path ?? '').trim();
  if (s.isEmpty) return false;
  if (isVideoContentPath(s)) return false;
  if (s.startsWith('memory://') ||
      s.startsWith('file:') ||
      (!s.startsWith('http') && s.contains(RegExp(r'[/\\]')))) {
    return true;
  }
  return isDirectPlayableVideoUrl(s);
}

/// 设置日志用：单轮 waitJob 结果（不含 query，避免签名串）。
String formatVideoPollLog({required int round, required VideoJob job}) {
  final id = job.jobId.trim().isEmpty ? '-' : job.jobId.trim();
  final status = switch (job.status) {
    VideoJobWireStatus.queued => 'queued',
    VideoJobWireStatus.inProgress => 'in_progress',
    VideoJobWireStatus.completed => 'completed',
    VideoJobWireStatus.failed => 'failed',
  };
  final progress = job.progress;
  final progressText = progress == null
      ? '-'
      : (progress == progress.roundToDouble()
          ? progress.round().toString()
          : progress.toString());
  final playable = resolvePlayableVideoPath(job);
  final buf = StringBuffer(
    '轮询 #$round · job=$id · status=$status · progress=$progressText'
    ' · url=${redactUrlForLog(job.videoUrl)}'
    ' · remote=${redactUrlForLog(job.remoteVideoUrl)}'
    ' · playable=${redactUrlForLog(playable.isEmpty ? null : playable)}'
    ' · materialize=${job.needsMaterialize}',
  );
  final err = job.errorMessage?.trim() ?? '';
  if (err.isNotEmpty) buf.write(' · error=$err');
  return buf.toString();
}

/// 日志 URL：去掉 query / fragment，避免签名与一次性 token。
String redactUrlForLog(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty) return '-';
  final q = s.indexOf('?');
  final h = s.indexOf('#');
  var cut = s.length;
  if (q >= 0) cut = q;
  if (h >= 0 && h < cut) cut = h;
  final out = s.substring(0, cut).trim();
  return out.isEmpty ? '-' : out;
}

/// 轮询中可提前露出的可播地址。
String earlyPlayableVideoPath(VideoJob job) {
  final v = job.videoUrl ?? '';
  if (v.startsWith('memory://') ||
      (!v.startsWith('http') && v.contains(RegExp(r'[/\\]')))) {
    return v;
  }
  if (isDirectPlayableVideoUrl(job.remoteVideoUrl)) {
    return job.remoteVideoUrl!;
  }
  if (isDirectPlayableVideoUrl(job.videoUrl)) return job.videoUrl!;
  return '';
}

/// 优先直链 https，其次任意 https（含 /content，供重新加载鉴权）。
String pickRemoteVideoUrl(VideoJob job, [VideoItem? item]) {
  for (final c in [
    job.remoteVideoUrl,
    job.videoUrl,
    item?.remoteVideoUrl,
  ]) {
    final s = (c ?? '').trim();
    if (RegExp(r'^https?://', caseSensitive: false).hasMatch(s) &&
        !isVideoContentPath(s)) {
      return s;
    }
  }
  for (final c in [job.remoteVideoUrl, job.videoUrl, item?.remoteVideoUrl]) {
    final s = (c ?? '').trim();
    if (RegExp(r'^https?://', caseSensitive: false).hasMatch(s)) return s;
  }
  return '';
}

/// 完成态可播路径：localPath 优先，其次可播 videoUrl。
String resolvePlayableVideoPath(VideoJob job) {
  final local = job.localPath?.trim() ?? '';
  if (isPlayableVideoPath(local)) return local;
  final url = job.videoUrl?.trim() ?? '';
  if (isPlayableVideoPath(url)) return url;
  return '';
}

bool isVideoContentPath(String? url) {
  final s = (url ?? '').trim();
  if (s.isEmpty) return false;
  final path = s.replaceFirst(RegExp(r'^https?://[^/]+', caseSensitive: false), '');
  return RegExp(r'(?:^|/)(?:v1/)?videos/[^/]+/content/?$', caseSensitive: false)
      .hasMatch(path);
}

/// 从 `/videos/{id}/content`（含绝对 URL）解析 jobId。
String? extractVideoJobIdFromContentUrl(String? url) {
  final s = (url ?? '').trim();
  if (s.isEmpty) return null;
  final path =
      s.replaceFirst(RegExp(r'^https?://[^/]+', caseSensitive: false), '');
  final m = RegExp(
    r'(?:^|/)(?:v1/)?videos/([^/]+)/content/?$',
    caseSensitive: false,
  ).firstMatch(path);
  if (m == null) return null;
  final id = Uri.decodeComponent(m.group(1) ?? '').trim();
  return id.isEmpty ? null : id;
}

String resolveVideoContentUrl(String url, String? baseUrl) {
  final src = url.trim();
  if (src.isEmpty) return '';
  if (RegExp(r'^https?://', caseSensitive: false).hasMatch(src)) return src;
  final base = normalizeBaseUrl(baseUrl ?? '');
  if (base.isEmpty) return src;
  if (src.startsWith('/')) return '$base$src';
  return '$base/$src';
}

Map<String, dynamic>? _asStringKeyedMap(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

String? _mapUrl(Map<String, dynamic>? map, String key) {
  if (map == null) return null;
  final v = map[key];
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

String extractVideoUrl(Object? data) {
  if (data is! Map) return '';
  final m = Map<String, dynamic>.from(data);
  // 部分中转再包一层 / 两层 data
  var root = m;
  for (var i = 0; i < 2; i++) {
    final nested = root['data'];
    if (nested is Map && nested is! List) {
      root = Map<String, dynamic>.from(nested);
    } else {
      break;
    }
  }
  final videoObj = _asStringKeyedMap(root['video']) ??
      _asStringKeyedMap(m['video']);
  final videoArr0 = root['video'] is List && (root['video'] as List).isNotEmpty
      ? (root['video'] as List).first
      : (m['video'] is List && (m['video'] as List).isNotEmpty
          ? (m['video'] as List).first
          : null);
  final videoArrMap = _asStringKeyedMap(videoArr0);
  final fileOutput = _asStringKeyedMap(videoObj?['file_output']) ??
      _asStringKeyedMap(videoObj?['fileOutput']);
  final videos0 = root['videos'] is List && (root['videos'] as List).isNotEmpty
      ? _asStringKeyedMap((root['videos'] as List).first)
      : null;
  final output = _asStringKeyedMap(root['output']);
  final result = _asStringKeyedMap(root['result']);
  final metadata = _asStringKeyedMap(root['metadata']);
  final resultVideo = _asStringKeyedMap(result?['video']);
  final outputVideo = _asStringKeyedMap(output?['video']);

  // video 有时直接是 URL 字符串
  final videoAsString = root['video'] is String
      ? (root['video'] as String).trim()
      : (m['video'] is String ? (m['video'] as String).trim() : '');

  final candidates = <String?>[
    _mapUrl(videoObj, 'url'),
    _mapUrl(fileOutput, 'url'),
    _mapUrl(videoObj, 'download_url'),
    _mapUrl(videoObj, 'downloadUrl'),
    _mapUrl(videoObj, 'play_url'),
    _mapUrl(videoObj, 'playUrl'),
    _mapUrl(videoObj, 'file_url'),
    _mapUrl(videoObj, 'fileUrl'),
    _mapUrl(videoObj, 'uri'),
    _mapUrl(videoObj, 'src'),
    videoAsString.isNotEmpty ? videoAsString : null,
    _mapUrl(root, 'video_url'),
    _mapUrl(root, 'videoUrl'),
    _mapUrl(videoArrMap, 'url'),
    _mapUrl(videos0, 'url'),
    _mapUrl(resultVideo, 'url'),
    _mapUrl(outputVideo, 'url'),
    _mapUrl(metadata, 'url'),
    _mapUrl(output, 'url'),
    _mapUrl(result, 'url'),
    _mapUrl(root, 'url'),
    _mapUrl(m, 'url'),
    _mapUrl(videoObj, 'public_url'),
    _mapUrl(videoObj, 'publicUrl'),
    _mapUrl(root, 'public_url'),
    _mapUrl(root, 'publicUrl'),
    _mapUrl(root, 'file_url'),
    _mapUrl(root, 'fileUrl'),
    _mapUrl(root, 'download_url'),
    _mapUrl(root, 'downloadUrl'),
    _mapUrl(videoArrMap, 'public_url'),
  ]
      .whereType<String>()
      .map(_normalizeExtractedVideoUrl)
      .where((v) => v.isNotEmpty)
      .toList();

  for (final u in candidates) {
    if (isDirectPlayableVideoUrl(u)) return u;
  }
  for (final u in candidates) {
    if (RegExp(r'^https?://', caseSensitive: false).hasMatch(u)) return u;
  }
  // 最后兜底：深搜 JSON 里第一个像 mp4/vidgen 的 https
  final deep = _deepFindPlayableVideoUrl(m);
  if (deep.isNotEmpty) return deep;
  return candidates.isEmpty ? '' : candidates.first;
}

String _normalizeExtractedVideoUrl(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return '';
  if (s.startsWith('//')) s = 'https:$s';
  return s;
}

/// 递归找可直链播放的 https（中转字段名五花八门时兜底）。
String _deepFindPlayableVideoUrl(Object? node, {int depth = 0}) {
  if (node == null || depth > 6) return '';
  if (node is String) {
    final s = _normalizeExtractedVideoUrl(node);
    if (isDirectPlayableVideoUrl(s) &&
        (s.contains('.mp4') ||
            s.contains('vidgen') ||
            s.contains('/video'))) {
      return s;
    }
    return '';
  }
  if (node is List) {
    for (final item in node) {
      final found = _deepFindPlayableVideoUrl(item, depth: depth + 1);
      if (found.isNotEmpty) return found;
    }
    return '';
  }
  if (node is Map) {
    for (final entry in node.entries) {
      final found = _deepFindPlayableVideoUrl(entry.value, depth: depth + 1);
      if (found.isNotEmpty) return found;
    }
  }
  return '';
}

/// 展开中转常见的 `data` 包层（最多两层），外→内。
List<Map<String, dynamic>> _videoJobLayers(Map<String, dynamic> root) {
  final layers = <Map<String, dynamic>>[root];
  var cur = root;
  for (var i = 0; i < 2; i++) {
    final nested = cur['data'];
    if (nested is Map && nested is! List) {
      cur = Map<String, dynamic>.from(nested);
      layers.add(cur);
    } else {
      break;
    }
  }
  return layers;
}

VideoJob normalizeVideoJob(Object? data, {String fallbackId = ''}) {
  if (data is! Map) {
    return VideoJob(jobId: fallbackId);
  }
  final m = Map<String, dynamic>.from(data);
  final layers = _videoJobLayers(m);
  final root = layers.last;
  final jobId = extractVideoJobId(data);

  // status：优先最内层非空；若内层无 status 而外层有（如 done + data.video），保留外层。
  // 若多层都有，优先终态（completed/failed）。
  String? statusRaw;
  for (final layer in layers.reversed) {
    final s = layer['status']?.toString().trim() ?? '';
    if (s.isEmpty) continue;
    final norm = VideoJobWireStatus.normalize(s);
    if (statusRaw == null || norm.isTerminal) {
      statusRaw = s;
      if (norm.isTerminal) break;
    }
  }
  // 无 status 但已有可播直链时，视为完成（部分中转只给 url）
  final videoUrl = extractVideoUrl(data);
  var status = VideoJobWireStatus.normalize(statusRaw);
  if ((statusRaw == null || statusRaw.isEmpty) &&
      videoUrl.isNotEmpty &&
      isDirectPlayableVideoUrl(videoUrl)) {
    status = VideoJobWireStatus.completed;
  }

  Object? progressRaw;
  for (final layer in layers.reversed) {
    progressRaw =
        layer['progress'] ?? layer['percent'] ?? layer['percentage'];
    if (progressRaw != null) break;
  }
  double? progress;
  if (progressRaw is num) {
    progress = progressRaw.toDouble();
  } else if (progressRaw != null) {
    progress = double.tryParse(progressRaw.toString());
  }

  String? errorMessage;
  if (status == VideoJobWireStatus.failed) {
    var msg = extractApiErrorMessage(root['error']);
    if (msg.isEmpty) msg = extractApiErrorMessage(root);
    if (msg.isEmpty) {
      for (final layer in layers) {
        if (layer['status']?.toString() == 'expired') {
          msg = '任务已过期';
          break;
        }
      }
    }
    if (msg.isEmpty) msg = '视频生成失败';
    errorMessage = msg;
  }
  return VideoJob(
    jobId: jobId.isNotEmpty ? jobId : fallbackId,
    status: status,
    progress: progress,
    videoUrl: videoUrl.isNotEmpty ? videoUrl : null,
    errorMessage: errorMessage,
  );
}
