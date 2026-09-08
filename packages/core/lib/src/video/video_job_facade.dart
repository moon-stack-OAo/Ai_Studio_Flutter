import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../chat/chat_errors.dart';
import '../chat/generation_gates.dart';
import '../chat/generation_runtime.dart';
import '../logging/app_log_entry.dart';
import '../logging/app_log_level.dart';
import '../logging/app_log_repository.dart';
import '../provider/agnes_profile.dart';
import '../provider/provider_config.dart';
import '../provider/provider_connection.dart';
import '../provider/provider_models_cache.dart';
import '../provider/provider_repository.dart';
import '../provider/xai_profile.dart';
import '../security/safe_http_client.dart';
import 'video_client.dart';
import 'video_models.dart';
import 'video_resume.dart';
import 'video_session_repository.dart';

/// 生视频任务编排（无 UI 绑定，DESIGN.md §5.1）。
///
/// 持有 generate / stop / resume / abandon / reload、参数状态、能力探测与
/// [ProviderModelsCache]；app 层 [ChangeNotifier] 仅做薄包装与平台 IO。
class VideoJobFacade {
  VideoJobFacade({
    required ProviderRepository providers,
    required VideoSessionRepository sessions,
    required this.generation,
    AppLogRepository? appLogs,
    OpenAiCompatibleVideoClient? videoClient,
    http.Client Function()? createHttpClient,
    VoidCallback? onModelsChanged,
  })  : _providers = providers,
        _sessions = sessions,
        _appLogs = appLogs,
        _ownsClient = videoClient == null,
        _videoClient = videoClient ??
            OpenAiCompatibleVideoClient(logs: appLogs),
        _createHttpClient = createHttpClient ?? createSafeHttpClient,
        modelsCache = ProviderModelsCache(
          providers: providers,
          onChanged: onModelsChanged,
        );

  final ProviderRepository _providers;
  final VideoSessionRepository _sessions;
  final AppLogRepository? _appLogs;
  final GenerationRuntime generation;
  final OpenAiCompatibleVideoClient _videoClient;
  final bool _ownsClient;
  final http.Client Function() _createHttpClient;

  final ProviderModelsCache modelsCache;

  bool _manualCancel = false;
  bool _autoResumeStarted = false;
  bool _disposed = false;
  final Set<String> _reloadingIds = {};

  int _duration = 10;
  String _size = '1280x720';
  String _aspectRatio = '16:9';
  String _resolution = '720p';
  String _promptDraft = '';
  bool _hasReferenceImage = false;

  static const defaultDurationOptions = <int>[5, 10, 20];

  static const defaultSizeOptions = <String>[
    '1280x720',
    '720x1280',
    '1024x1024',
  ];

  static const defaultAspectOptions = <String>[
    '16:9',
    '9:16',
    '1:1',
  ];

  static const resolutionOptions = <String>['480p', '720p', '1080p'];

  /// 兼容旧接线。
  static const durationOptions = defaultDurationOptions;
  static const sizeOptions = defaultSizeOptions;
  static const aspectOptions = defaultAspectOptions;

  OpenAiCompatibleVideoClient get videoClient => _videoClient;

  VideoSessionRepository get sessions => _sessions;

  ProviderRepository get providers => _providers;

  int get duration => _duration;
  String get size => _size;
  String get aspectRatio => _aspectRatio;
  String get resolution => _resolution;
  String get promptDraft => _promptDraft;
  bool get hasReferenceImage => _hasReferenceImage;

  bool get isGeneratingActiveSession =>
      generation.isCurrent(_sessions.activeId);

  bool get hasPendingResume => _sessions.pendingResumeItems.isNotEmpty;

  bool isReloading(String itemId) => _reloadingIds.contains(itemId);

  bool get canGenerate => canGenerateVideo(
        generation: generation,
        activeSessionId: _sessions.activeId,
        hasConfiguredVideoProvider: _providers.hasConfiguredVideoProvider,
        promptDraft: _promptDraft,
        hasReferenceImage: _hasReferenceImage,
      );

  ActiveVideoCredentials? get _videoCreds => _providers.activeVideoCredentials;

  bool get isAgnesActive {
    final c = _videoCreds;
    if (c == null) return false;
    return isAgnesProvider(baseUrl: c.baseUrl, videoModel: c.videoModel);
  }

  bool get supportsReferenceImage => true;

  bool get isXaiVideoActive {
    final c = _videoCreds;
    if (c == null) return false;
    return isXaiVideoProvider(
      providerType: c.type,
      baseUrl: c.baseUrl,
      videoModel: c.videoModel,
    );
  }

  bool get useAspectRatio {
    if (_videoCreds == null) return false;
    if (isAgnesActive) return true;
    return isXaiVideoActive;
  }

  bool get useResolution => isXaiVideoActive;

  bool get showSize {
    if (isAgnesActive) return true;
    return !useAspectRatio;
  }

  List<int> get activeDurationOptions =>
      isAgnesActive ? agnesVideoDurationOptions : defaultDurationOptions;

  List<String> get activeSizeOptions {
    if (isAgnesActive) {
      return agnesVideoSizeOptionsFor(_videoCreds?.videoModel);
    }
    return defaultSizeOptions;
  }

  List<String> get activeAspectOptions =>
      isAgnesActive ? agnesVideoRatios : defaultAspectOptions;

  String get promptAssistMode =>
      _hasReferenceImage ? 'img2video' : 'txt2video';

  void setDuration(int value, {VoidCallback? onNotify}) {
    if (value == _duration) return;
    _duration = value;
    onNotify?.call();
  }

  void setSize(String value, {VoidCallback? onNotify}) {
    if (value == _size) return;
    _size = value;
    onNotify?.call();
  }

  void setAspectRatio(String value, {VoidCallback? onNotify}) {
    if (value == _aspectRatio) return;
    _aspectRatio = value;
    onNotify?.call();
  }

  void setResolution(String value, {VoidCallback? onNotify}) {
    if (value == _resolution) return;
    _resolution = value;
    onNotify?.call();
  }

  void setPromptDraft(String value, {VoidCallback? onNotify}) {
    if (value == _promptDraft) return;
    _promptDraft = value;
    onNotify?.call();
  }

  void applyPromptPreset(String prompt, {VoidCallback? onNotify}) {
    final text = prompt.trim();
    if (text.isEmpty) return;
    _promptDraft = text;
    onNotify?.call();
  }

  /// 参考图由 app 持有字节 / 路径；此处仅同步门闩与 promptAssist 用的布尔态。
  void setHasReferenceImage(bool value, {VoidCallback? onNotify}) {
    if (value == _hasReferenceImage) return;
    _hasReferenceImage = value;
    onNotify?.call();
  }

  /// 切换提供商后校正参数落在可选范围内（同步；由 app [onNotify] 刷新 UI）。
  void syncParamsToActiveProvider({VoidCallback? onNotify}) {
    var changed = false;
    final durations = activeDurationOptions;
    if (!durations.contains(_duration)) {
      _duration = isAgnesActive
          ? agnesVideoDurationDefault
          : durations.contains(10)
              ? 10
              : durations.first;
      changed = true;
    }
    final sizes = activeSizeOptions;
    if (sizes.isNotEmpty && !sizes.contains(_size)) {
      _size = isAgnesActive
          ? normalizeAgnesVideoSize(_size, videoModel: _videoCreds?.videoModel)
          : sizes.first;
      if (!sizes.contains(_size)) _size = sizes.first;
      changed = true;
    }
    final aspects = activeAspectOptions;
    if (aspects.isNotEmpty && !aspects.contains(_aspectRatio)) {
      _aspectRatio = aspects.first;
      changed = true;
    }
    if (useResolution && !resolutionOptions.contains(_resolution)) {
      _resolution = '720p';
      changed = true;
    }
    if (changed) onNotify?.call();
  }

  /// 拉取生视频模型列表（仅 [ProviderConfig.canVideo]）。
  Future<List<ProviderModelInfo>> loadVideoModels({
    bool force = false,
    bool silentRefreshIfStale = true,
  }) {
    return modelsCache.load(
      force: force,
      silentRefreshIfStale: silentRefreshIfStale,
      canUse: (p) => p.canVideo,
    );
  }

  void stop() {
    _manualCancel = true;
    final sid = generation.sessionId;
    if (sid == null) return;
    generation.abort(sid);
  }

  /// 启动后静默恢复 pending_resume（仅一次）。
  Future<void> startAutoResumeIfNeeded({
    required VoidCallback onNotify,
    void Function(String? message)? onBanner,
    void Function(String? message)? onInfo,
  }) async {
    if (_disposed || _autoResumeStarted) return;
    _autoResumeStarted = true;
    if (_sessions.pendingResumeItems.isEmpty) return;
    if (generation.busy) return;
    onInfo?.call('正在恢复未完成的视频任务…');
    if (_disposed) return;
    await _runResumeAll(
      onNotify: onNotify,
      onBanner: onBanner,
      onInfo: onInfo,
    );
  }

  Future<void> resumePending({
    required VoidCallback onNotify,
    void Function(String? message)? onBanner,
    void Function(String? message)? onInfo,
  }) async {
    if (generation.busy) {
      onBanner?.call('当前有任务进行中，请稍后再试');
      return;
    }
    if (_sessions.pendingResumeItems.isEmpty) {
      onInfo?.call('没有可恢复的任务');
      return;
    }
    onBanner?.call(null);
    onInfo?.call('正在恢复未完成的视频任务…');
    await _runResumeAll(
      onNotify: onNotify,
      onBanner: onBanner,
      onInfo: onInfo,
    );
  }

  Future<void> resumeItem(
    String sessionId,
    String itemId, {
    required VoidCallback onNotify,
    void Function(String? message)? onBanner,
    void Function(String? message)? onInfo,
  }) async {
    if (generation.busy) {
      onBanner?.call('当前有任务进行中，请稍后再试');
      return;
    }
    final session =
        _sessions.sessions.where((s) => s.id == sessionId).firstOrNull;
    final item = session?.items.where((i) => i.id == itemId).firstOrNull;
    if (item == null || (item.jobId?.trim().isEmpty ?? true)) {
      onBanner?.call('无法恢复：缺少任务 ID');
      return;
    }
    await _sessions.updateItem(
      sessionId,
      itemId,
      status: VideoItemStatus.pendingResume,
      needsResume: true,
      errorMessage: '正在恢复轮询…',
    );
    onBanner?.call(null);
    await _runResumeAll(
      onNotify: onNotify,
      onBanner: onBanner,
      onInfo: onInfo,
    );
  }

  Future<void> abandonItem(
    String sessionId,
    String itemId, {
    VoidCallback? onNotify,
  }) async {
    await _sessions.abandonItem(sessionId, itemId);
    onNotify?.call();
  }

  /// 从 assetStore / 本地路径 / 直链 https 读取视频字节（供另存 / 打开）。
  Future<Uint8List?> resolveVideoBytes(VideoItem item) async {
    final local = item.localPath ?? item.videoUrl;
    if (local != null &&
        local.isNotEmpty &&
        !local.startsWith('http') &&
        !local.startsWith('data:')) {
      final fromStore = await _sessions.assetStore.read(local);
      if (fromStore != null) return fromStore;
      if (!local.startsWith('memory://')) {
        try {
          final f = File(local);
          if (await f.exists()) return f.readAsBytes();
        } catch (_) {}
      }
    }
    final remote = (item.remoteVideoUrl ?? item.videoUrl ?? '').trim();
    if (RegExp(r'^https?://', caseSensitive: false).hasMatch(remote) &&
        !isVideoContentPath(remote)) {
      final httpClient = _createHttpClient();
      try {
        final res = await httpClient.get(Uri.parse(remote));
        if (res.statusCode >= 200 && res.statusCode < 300) {
          return res.bodyBytes;
        }
      } catch (_) {
      } finally {
        try {
          httpClient.close();
        } catch (_) {}
      }
    }
    return null;
  }

  /// 重新鉴权拉流 / materialize 落盘。
  Future<void> reloadVideo(
    VideoItem item, {
    required VoidCallback onNotify,
    void Function(String? message)? onBanner,
    void Function(String? message)? onInfo,
  }) async {
    if (_disposed) return;
    final sessionId = _sessions.activeId;
    if (sessionId.isEmpty || item.id.isEmpty) return;
    if (_reloadingIds.contains(item.id)) return;
    if (generation.busy) {
      onBanner?.call('当前有任务进行中，请稍后再试');
      return;
    }

    final remote = (item.remoteVideoUrl ?? item.videoUrl ?? '').trim();
    final jobId = item.jobId?.trim() ?? '';
    final provider = _resolveProviderForItem(item);
    final canAuthFetch = provider != null &&
        provider.baseUrl.trim().isNotEmpty &&
        (jobId.isNotEmpty || isVideoContentPath(remote));

    if (!canAuthFetch) {
      if (remote.isNotEmpty &&
          !isVideoContentPath(remote) &&
          isDirectPlayableVideoUrl(remote)) {
        await _sessions.completeItem(
          sessionId,
          item.id,
          videoUrl: remote,
          remoteVideoUrl: remote,
          needsMaterialize: false,
        );
        onInfo?.call('视频已重新加载');
        onNotify();
        return;
      }
      onBanner?.call('无法重新加载，请重新生成');
      return;
    }

    _reloadingIds.add(item.id);
    onBanner?.call(null);
    onInfo?.call('正在重新加载视频…');
    onNotify();

    final httpClient = _createHttpClient();
    var cancelled = false;
    final token = generation.begin(sessionId, () {
      cancelled = true;
      try {
        httpClient.close();
      } catch (_) {}
    });

    try {
      final src = remote.isNotEmpty
          ? remote
          : (jobId.isNotEmpty ? '/videos/$jobId/content' : '');
      if (src.isEmpty) {
        onBanner?.call('无法重新加载，请重新生成');
        return;
      }
      final out = await _videoClient.materialize(
        VideoJob(
          jobId: jobId,
          status: VideoJobWireStatus.completed,
          videoUrl: src,
          remoteVideoUrl: remote.isEmpty ? null : remote,
        ),
        baseUrl: provider.baseUrl,
        apiKey: provider.apiKey,
        providerType: provider.type,
        assetStore: _sessions.assetStore,
        materializeId: item.id,
        client: httpClient,
      );
      if (cancelled || _disposed) return;

      final playable = resolvePlayableVideoPath(out);
      final nextRemote = pickRemoteVideoUrl(out, item);
      if (playable.isNotEmpty && !out.needsMaterialize) {
        await _sessions.completeItem(
          sessionId,
          item.id,
          videoUrl: playable,
          remoteVideoUrl: nextRemote.isEmpty ? null : nextRemote,
          localPath: out.localPath ??
              (playable.startsWith('http') ? null : playable),
          needsMaterialize: false,
        );
        onInfo?.call('视频已重新加载');
      } else {
        final err = (out.errorMessage?.trim().isNotEmpty == true)
            ? out.errorMessage!
            : '重新加载失败，请重新生成';
        final nextJobId =
            (out.jobId.isNotEmpty ? out.jobId : jobId).trim();
        await _sessions.markNeedsMaterialize(
          sessionId,
          item.id,
          errorMessage: err,
          remoteVideoUrl: nextRemote.isEmpty ? null : nextRemote,
          jobId: nextJobId.isNotEmpty ? nextJobId : null,
        );
        _logError(err);
        onBanner?.call(err);
      }
    } catch (e) {
      if (isAbortLike(e) || e is ChatAbortException || cancelled) return;
      final err = toChatErrorMessage(e, '重新加载失败');
      await _sessions.markNeedsMaterialize(
        sessionId,
        item.id,
        errorMessage: err,
        remoteVideoUrl: remote.isEmpty ? null : remote,
        jobId: jobId.isNotEmpty ? jobId : null,
      );
      _logError(err);
      onBanner?.call(err);
    } finally {
      _reloadingIds.remove(item.id);
      generation.end(sessionId, token);
      try {
        httpClient.close();
      } catch (_) {}
      onNotify();
    }
  }

  ProviderConfig? _resolveProviderForItem(VideoItem item) {
    if (item.providerId.isNotEmpty) {
      for (final p in _providers.providers) {
        if (p.id == item.providerId) return p;
      }
    }
    return _providers.activeProvider;
  }

  /// 文生 / 图生编排。参考图由 app 先读成 [imageBytes] 再传入。
  ///
  /// [bannerOnJobError] 为 true 时，完成态 error / 无 jobId 失败也会 [onBanner]
  ///（移动端）；桌面可保持 false，仅写日志。
  ///
  /// 未显式传入 [duration] / [size] / [aspectRatio] / [resolution] 时用 facade
  /// 当前参数；[prompt] 默认取 [promptDraft]（调用方也可传入快照）。
  Future<void> generate({
    String? prompt,
    int? duration,
    String? size,
    String? aspectRatio,
    String? resolution,
    Uint8List? imageBytes,
    String? imageFileName,
    required VoidCallback onNotify,
    void Function(String? message)? onBanner,
    void Function(String? message)? onInfo,
    bool bannerOnJobError = false,
    bool clearPromptDraft = true,
  }) async {
    if (_disposed) return;
    final text = (prompt ?? _promptDraft).trim();
    final useDuration = duration ?? _duration;
    final useSize = size ?? _size;
    final useAspect = aspectRatio ?? _aspectRatio;
    final useRes = resolution ?? _resolution;

    final creds = _providers.activeVideoCredentials;
    if (creds == null) {
      onBanner?.call('请先配置提供商视频模型与 API Key');
      return;
    }
    if (generation.busy) {
      onBanner?.call('当前有任务进行中，请稍后再试');
      return;
    }

    final refBytes =
        (imageBytes != null && imageBytes.isNotEmpty) ? imageBytes : null;
    final mode =
        refBytes != null ? VideoGenMode.image : VideoGenMode.text;
    if (mode == VideoGenMode.text && text.isEmpty) {
      onBanner?.call('请输入提示词');
      return;
    }
    final refName = (imageFileName ?? 'image.png').trim();
    final effectiveRefName = refName.isEmpty ? 'image.png' : refName;

    var session = _sessions.activeSession;
    session ??= await _sessions.createSession();
    if (_disposed) return;
    final sessionId = session.id;

    if (clearPromptDraft) {
      _promptDraft = '';
    }
    onBanner?.call(null);
    onInfo?.call(null);
    onNotify();

    final agnes = isAgnesProvider(
      baseUrl: creds.baseUrl,
      videoModel: creds.videoModel,
    );
    final xai = isXaiVideoProvider(
      providerType: creds.type,
      baseUrl: creds.baseUrl,
      videoModel: creds.videoModel,
    );
    final passAspect = agnes || xai;
    final passSize = agnes || !passAspect;
    final passResolution = xai ? useRes : null;
    final effectiveSize = agnes
        ? normalizeAgnesVideoSize(useSize, videoModel: creds.videoModel)
        : useSize;
    final effectiveDuration =
        agnes ? clampAgnesVideoSeconds(useDuration) : useDuration;

    final pending = await _sessions.appendLoadingItem(
      sessionId,
      mode: mode,
      prompt: text,
      model: creds.videoModel,
      providerId: creds.providerId,
      providerName: creds.providerName,
      duration: effectiveDuration,
      size: passSize ? effectiveSize : null,
      aspectRatio: passAspect ? useAspect : null,
      resolution: passResolution,
    );
    if (pending == null || _disposed) return;

    final httpClient = _createHttpClient();
    var cancelled = false;
    _manualCancel = false;
    final token = generation.begin(sessionId, () {
      cancelled = true;
      try {
        httpClient.close();
      } catch (_) {}
    });
    onNotify();

    try {
      final job = await _videoClient.generate(
        baseUrl: creds.baseUrl,
        apiKey: creds.apiKey,
        model: creds.videoModel,
        prompt: text,
        providerType: creds.type,
        mode: mode,
        imageBytes: refBytes,
        imageFileName: effectiveRefName,
        duration: effectiveDuration,
        size: passSize ? effectiveSize : null,
        aspectRatio: passAspect ? useAspect : null,
        resolution: passResolution,
        assetStore: _sessions.assetStore,
        materializeId: pending.id,
        client: httpClient,
        isCancelled: () => cancelled || _manualCancel,
        onProgress: (j) {
          final early = earlyPlayableVideoPath(j);
          final live = _sessions.sessions
              .where((s) => s.id == sessionId)
              .expand((s) => s.items)
              .where((i) => i.id == pending.id)
              .firstOrNull;
          final earlyUrl = early.isEmpty ? null : early;
          final remote = early.isNotEmpty &&
                  RegExp(r'^https?://', caseSensitive: false).hasMatch(early)
              ? early
              : j.remoteVideoUrl;
          unawaited(
            _sessions.updateItem(
              sessionId,
              pending.id,
              status: VideoItemStatus.loading,
              progress: j.progress,
              jobId: j.jobId.isNotEmpty ? j.jobId : null,
              videoUrl: earlyUrl != null && earlyUrl != live?.videoUrl
                  ? earlyUrl
                  : null,
              remoteVideoUrl:
                  remote != null && remote != live?.remoteVideoUrl
                      ? remote
                      : null,
              persist: j.jobId.isNotEmpty || early.isNotEmpty,
            ),
          );
          onNotify();
        },
      );

      await applyVideoJobCompletion(
        repository: _sessions,
        sessionId: sessionId,
        item: pending,
        job: job,
      );
      final live = _sessions.sessions
          .where((s) => s.id == sessionId)
          .expand((s) => s.items)
          .where((i) => i.id == pending.id)
          .firstOrNull;
      if (live?.status == VideoItemStatus.error) {
        final msg = live?.errorMessage ?? job.errorMessage ?? '视频生成失败';
        if (bannerOnJobError) {
          onBanner?.call(msg);
        }
        _logError(msg);
      }
    } on ChatAbortException {
      await _onAbort(sessionId, pending.id, onInfo: onInfo);
    } on VideoJobTimeoutException catch (e) {
      await _sessions.markPendingResume(
        sessionId,
        pending.id,
        errorMessage: e.message,
      );
      onInfo?.call(e.message);
    } catch (e) {
      if (isAbortLike(e) || cancelled || _manualCancel) {
        await _onAbort(sessionId, pending.id, onInfo: onInfo);
      } else {
        final msg = toChatErrorMessage(e, '生成失败');
        final live = _sessions.activeSession?.items
            .where((i) => i.id == pending.id)
            .firstOrNull;
        final jid = live?.jobId?.trim() ?? '';
        if (jid.isNotEmpty) {
          await _sessions.markPendingResume(
            sessionId,
            pending.id,
            errorMessage: msg,
          );
          onInfo?.call('任务已创建，可稍后恢复轮询');
        } else {
          await _sessions.failItem(sessionId, pending.id, msg);
          if (bannerOnJobError) {
            onBanner?.call(msg);
          }
        }
        _logError(msg);
      }
    } finally {
      generation.end(sessionId, token);
      try {
        httpClient.close();
      } catch (_) {}
      onNotify();
    }
  }

  Future<void> _runResumeAll({
    required VoidCallback onNotify,
    void Function(String? message)? onBanner,
    void Function(String? message)? onInfo,
  }) async {
    if (_disposed) return;
    final pending = _sessions.pendingResumeItems;
    if (pending.isEmpty) {
      onInfo?.call(null);
      return;
    }
    final bindSessionId = pending
            .where((e) => e.sessionId == _sessions.activeId)
            .map((e) => e.sessionId)
            .firstOrNull ??
        pending.first.sessionId;

    final httpClient = _createHttpClient();
    var cancelled = false;
    final token = generation.begin(bindSessionId, () {
      cancelled = true;
      try {
        httpClient.close();
      } catch (_) {}
    });
    _manualCancel = false;
    onNotify();

    try {
      final results = await resumePendingJobs(
        repository: _sessions,
        client: _videoClient,
        resolveProvider: defaultVideoProviderResolver(
          providers: () => _providers.providers,
          activeProvider: () => _providers.activeProvider,
        ),
        isCancelled: () => cancelled || _manualCancel,
        httpClient: httpClient,
        onProgress: (sessionId, itemId, job) {
          onNotify();
        },
      );
      final failed = results.where((r) => r.error != null).length;
      final ok = results.where((r) => r.error == null).length;
      if (ok > 0 && failed == 0) {
        onInfo?.call('已恢复 $ok 个任务');
      } else if (ok > 0) {
        onInfo?.call('已恢复 $ok 个，失败 $failed 个');
      } else {
        onInfo?.call(null);
      }
    } catch (e) {
      if (!isAbortLike(e) && e is! ChatAbortException) {
        final msg = toChatErrorMessage(e, '恢复任务失败');
        onBanner?.call(msg);
        _logError(msg);
      }
      onInfo?.call(null);
    } finally {
      generation.end(bindSessionId, token);
      try {
        httpClient.close();
      } catch (_) {}
      onNotify();
    }
  }

  Future<void> _onAbort(
    String sessionId,
    String itemId, {
    void Function(String? message)? onInfo,
  }) async {
    final live = _sessions.sessions
        .where((s) => s.id == sessionId)
        .expand((s) => s.items)
        .where((i) => i.id == itemId)
        .firstOrNull;
    final jid = live?.jobId?.trim() ?? '';
    if (jid.isNotEmpty) {
      await _sessions.markPendingResume(
        sessionId,
        itemId,
        errorMessage: '已停止轮询，可手动恢复',
      );
      onInfo?.call('已停止轮询，可手动恢复');
    } else {
      await _sessions.failItem(sessionId, itemId, '已取消');
    }
  }

  void _logError(String msg) {
    final logs = _appLogs;
    if (logs == null) return;
    unawaited(
      logs.append(
        level: AppLogLevel.error,
        source: AppLogSources.video,
        message: msg,
      ),
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _manualCancel = true;
    final sid = generation.sessionId;
    if (sid != null) {
      generation.abort(sid);
    }
    modelsCache.dispose();
    if (_ownsClient) _videoClient.close();
  }
}

extension _FirstOrNullVideoFacade<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
