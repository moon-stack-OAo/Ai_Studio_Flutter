import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../widgets/provider_models_cache.dart';

/// Material 生视频页状态机（app 层，不进 core）。
class VideoController extends ChangeNotifier {
  VideoController({
    required ProviderRepository providerRepository,
    required VideoSessionRepository sessionRepository,
    required this.generation,
    AppLogRepository? appLogRepository,
    OpenAiCompatibleVideoClient? videoClient,
    ImagePicker? imagePicker,
  })  : _providers = providerRepository,
        _sessions = sessionRepository,
        _appLogs = appLogRepository,
        _ownsClient = videoClient == null,
        _videoClient = videoClient ?? OpenAiCompatibleVideoClient(),
        _picker = imagePicker ?? ImagePicker() {
    _modelsCache = ProviderModelsCache(
      providers: _providers,
      onChanged: _notify,
    );
  }

  final ProviderRepository _providers;
  final VideoSessionRepository _sessions;
  final AppLogRepository? _appLogs;
  final GenerationRuntime generation;
  final OpenAiCompatibleVideoClient _videoClient;
  final bool _ownsClient;
  final ImagePicker _picker;
  late final ProviderModelsCache _modelsCache;

  String? _bannerError;
  String? _bannerInfo;
  int _duration = 10;
  String _size = '1280x720';
  String _aspectRatio = '16:9';
  String _resolution = '720p';
  String _promptDraft = '';
  Uint8List? _refBytes;
  String _refFileName = 'image.png';
  bool _autoResumeStarted = false;
  bool _manualCancel = false;
  bool _disposed = false;
  final Set<String> _reloadingIds = {};

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

  String? get bannerError => _bannerError;
  String? get bannerInfo => _bannerInfo;
  int get duration => _duration;
  String get size => _size;
  String get aspectRatio => _aspectRatio;
  String get resolution => _resolution;
  String get promptDraft => _promptDraft;
  Uint8List? get refBytes => _refBytes;
  bool get hasRefImage => _refBytes != null && _refBytes!.isNotEmpty;

  VideoSessionRepository get sessions => _sessions;
  ProviderRepository get providers => _providers;
  ProviderModelsCache get modelsCache => _modelsCache;

  bool get isGeneratingActiveSession =>
      generation.isCurrent(_sessions.activeId);

  bool get canGenerate {
    if (generation.isCurrent(_sessions.activeId)) return false;
    if (generation.busy) return false;
    if (!_providers.hasConfiguredVideoProvider) return false;
    if (hasRefImage) return true;
    return _promptDraft.trim().isNotEmpty;
  }

  ActiveVideoCredentials? get _videoCreds => _providers.activeVideoCredentials;

  bool get isAgnesActive {
    final c = _videoCreds;
    if (c == null) return false;
    return isAgnesProvider(baseUrl: c.baseUrl, videoModel: c.videoModel);
  }

  bool get supportsReferenceImage => true;

  bool get useAspectRatio {
    final creds = _videoCreds;
    if (creds == null) return false;
    if (isAgnesActive) return true;
    return creds.type == ProviderType.xai;
  }

  bool get useResolution {
    final creds = _videoCreds;
    return creds?.type == ProviderType.xai;
  }

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

  bool get hasPendingResume => _sessions.pendingResumeItems.isNotEmpty;

  String get promptAssistMode => hasRefImage ? 'img2video' : 'txt2video';

  void applyPromptPreset(String prompt) {
    final text = prompt.trim();
    if (text.isEmpty) return;
    _promptDraft = text;
    notifyListeners();
  }

  void setPromptDraft(String value) {
    if (value == _promptDraft) return;
    _promptDraft = value;
    _notify();
  }

  Future<void> pickRefImage() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        _setBanner('参考图读取失败');
        return;
      }
      _refBytes = bytes;
      final name = file.name.trim();
      _refFileName = name.isEmpty ? 'image.png' : name;
      clearBannerError();
      _notify();
    } catch (_) {
      _setBanner('无法选择参考图');
    }
  }

  void clearRefImage() {
    if (_refBytes == null) return;
    _refBytes = null;
    _refFileName = 'image.png';
    _notify();
  }

  void setDuration(int value) {
    if (value == _duration) return;
    _duration = value;
    _notify();
  }

  void setSize(String value) {
    if (value == _size) return;
    _size = value;
    _notify();
  }

  void setAspectRatio(String value) {
    if (value == _aspectRatio) return;
    _aspectRatio = value;
    _notify();
  }

  void setResolution(String value) {
    if (value == _resolution) return;
    _resolution = value;
    _notify();
  }

  /// 切换提供商后校正参数落在可选范围内。
  void syncParamsToActiveProvider() {
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
    if (changed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _notify());
    }
  }

  void clearBannerError() {
    if (_bannerError == null) return;
    _bannerError = null;
    _notify();
  }

  void clearBannerInfo() {
    if (_bannerInfo == null) return;
    _bannerInfo = null;
    _notify();
  }

  void _setBanner(String? message) {
    _bannerError = message;
    _notify();
  }

  void _setInfo(String? message) {
    _bannerInfo = message;
    _notify();
  }

  Future<void> createSession() async {
    await _sessions.createSession();
    clearBannerError();
  }

  Future<void> setActiveSession(String id) async {
    if (id == _sessions.activeId) return;
    await _sessions.setActive(id);
    clearBannerError();
    _notify();
  }

  Future<void> removeSession(String id) async {
    generation.abortIfSession(id);
    await _sessions.removeSession(id);
    clearBannerError();
  }

  Future<void> clearActiveItems() async {
    final sid = _sessions.activeId;
    if (sid.isEmpty) return;
    if (generation.isCurrent(sid)) {
      generation.abort(sid);
    }
    await _sessions.clearItems(sid);
    clearBannerError();
  }

  void stop() {
    _manualCancel = true;
    final sid = generation.sessionId;
    if (sid == null) return;
    generation.abort(sid);
  }

  /// 进入页后静默恢复 pending_resume。
  Future<void> startAutoResumeIfNeeded() async {
    if (_disposed || _autoResumeStarted) return;
    _autoResumeStarted = true;
    if (_sessions.pendingResumeItems.isEmpty) return;
    if (generation.busy) return;
    _setInfo('正在恢复未完成的视频任务…');
    if (_disposed) return;
    await _runResumeAll();
  }

  Future<void> resumePending() async {
    if (generation.busy) {
      _setBanner('当前有任务进行中，请稍后再试');
      return;
    }
    if (_sessions.pendingResumeItems.isEmpty) {
      _setInfo('没有可恢复的任务');
      return;
    }
    clearBannerError();
    _setInfo('正在恢复未完成的视频任务…');
    await _runResumeAll();
  }

  Future<void> resumeItem(String sessionId, String itemId) async {
    if (generation.busy) {
      _setBanner('当前有任务进行中，请稍后再试');
      return;
    }
    final session =
        _sessions.sessions.where((s) => s.id == sessionId).firstOrNull;
    final item = session?.items.where((i) => i.id == itemId).firstOrNull;
    if (item == null || (item.jobId?.trim().isEmpty ?? true)) {
      _setBanner('无法恢复：缺少任务 ID');
      return;
    }
    await _sessions.updateItem(
      sessionId,
      itemId,
      status: VideoItemStatus.pendingResume,
      needsResume: true,
      errorMessage: '正在恢复轮询…',
    );
    clearBannerError();
    await _runResumeAll();
  }

  Future<void> abandonItem(String sessionId, String itemId) async {
    await _sessions.abandonItem(sessionId, itemId);
    _notify();
  }

  Future<void> _runResumeAll() async {
    if (_disposed) return;
    final pending = _sessions.pendingResumeItems;
    if (pending.isEmpty) {
      clearBannerInfo();
      return;
    }
    final bindSessionId = pending
            .where((e) => e.sessionId == _sessions.activeId)
            .map((e) => e.sessionId)
            .firstOrNull ??
        pending.first.sessionId;

    final httpClient = http.Client();
    var cancelled = false;
    final token = generation.begin(bindSessionId, () {
      cancelled = true;
      try {
        httpClient.close();
      } catch (_) {}
    });
    _manualCancel = false;
    _notify();

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
          _notify();
        },
      );
      final failed = results.where((r) => r.error != null).length;
      final ok = results.where((r) => r.error == null).length;
      if (ok > 0 && failed == 0) {
        _setInfo('已恢复 $ok 个任务');
      } else if (ok > 0) {
        _setInfo('已恢复 $ok 个，失败 $failed 个');
      } else if (failed > 0 && !_manualCancel) {
        clearBannerInfo();
      } else {
        clearBannerInfo();
      }
    } catch (e) {
      if (!isAbortLike(e) && e is! ChatAbortException) {
        final msg = toChatErrorMessage(e, '恢复任务失败');
        _setBanner(msg);
        _logError(msg);
      }
      clearBannerInfo();
    } finally {
      generation.end(bindSessionId, token);
      try {
        httpClient.close();
      } catch (_) {}
      _notify();
    }
  }

  Future<void> generate() async {
    if (_disposed) return;
    final text = _promptDraft.trim();

    final creds = _providers.activeVideoCredentials;
    if (creds == null) {
      _setBanner('请先配置提供商视频模型与 API Key');
      return;
    }
    if (generation.busy) {
      _setBanner('当前有任务进行中，请稍后再试');
      return;
    }

    final ref = _refBytes;
    final mode =
        (ref != null && ref.isNotEmpty) ? VideoGenMode.image : VideoGenMode.text;
    if (mode == VideoGenMode.text && text.isEmpty) {
      _setBanner('请输入提示词');
      return;
    }
    final refFileName = _refFileName;

    var session = _sessions.activeSession;
    session ??= await _sessions.createSession();
    if (_disposed) return;
    final sessionId = session.id;

    clearBannerError();
    clearBannerInfo();
    _promptDraft = '';
    _notify();

    final agnes = isAgnesProvider(
      baseUrl: creds.baseUrl,
      videoModel: creds.videoModel,
    );
    final passAspect = useAspectRatio;
    final passSize = agnes || !passAspect;
    final passResolution = useResolution ? _resolution : null;
    final effectiveSize = agnes
        ? normalizeAgnesVideoSize(_size, videoModel: creds.videoModel)
        : _size;
    final effectiveDuration =
        agnes ? clampAgnesVideoSeconds(_duration) : _duration;

    final pending = await _sessions.appendLoadingItem(
      sessionId,
      mode: mode,
      prompt: text,
      model: creds.videoModel,
      providerId: creds.providerId,
      providerName: creds.providerName,
      duration: effectiveDuration,
      size: passSize ? effectiveSize : null,
      aspectRatio: passAspect ? _aspectRatio : null,
      resolution: passResolution,
    );
    if (pending == null || _disposed) return;

    final httpClient = http.Client();
    var cancelled = false;
    _manualCancel = false;
    final token = generation.begin(sessionId, () {
      cancelled = true;
      try {
        httpClient.close();
      } catch (_) {}
    });
    _notify();

    try {
      final job = await _videoClient.generate(
        baseUrl: creds.baseUrl,
        apiKey: creds.apiKey,
        model: creds.videoModel,
        prompt: text,
        providerType: creds.type,
        mode: mode,
        imageBytes: mode == VideoGenMode.image ? ref : null,
        imageFileName: refFileName,
        duration: effectiveDuration,
        size: passSize ? effectiveSize : null,
        aspectRatio: passAspect ? _aspectRatio : null,
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
          _notify();
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
        _setBanner(msg);
        _logError(msg);
      }
    } on ChatAbortException {
      await _onAbort(sessionId, pending.id);
    } on VideoJobTimeoutException catch (e) {
      await _sessions.markPendingResume(
        sessionId,
        pending.id,
        errorMessage: e.message,
      );
      _setInfo(e.message);
    } catch (e) {
      if (isAbortLike(e) || cancelled || _manualCancel) {
        await _onAbort(sessionId, pending.id);
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
          _setInfo('任务已创建，可稍后恢复轮询');
        } else {
          await _sessions.failItem(sessionId, pending.id, msg);
          _setBanner(msg);
        }
        _logError(msg);
      }
    } finally {
      generation.end(sessionId, token);
      try {
        httpClient.close();
      } catch (_) {}
      _notify();
    }
  }

  Future<void> _onAbort(String sessionId, String itemId) async {
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
      _setInfo('已停止轮询，可手动恢复');
    } else {
      await _sessions.failItem(sessionId, itemId, '已取消');
    }
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
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

  bool isReloading(String itemId) => _reloadingIds.contains(itemId);

  /// 重新鉴权拉流 / materialize 落盘。
  Future<void> reloadVideo(VideoItem item) async {
    if (_disposed) return;
    final sessionId = _sessions.activeId;
    if (sessionId.isEmpty || item.id.isEmpty) return;
    if (_reloadingIds.contains(item.id)) return;
    if (generation.busy) {
      _setBanner('当前有任务进行中，请稍后再试');
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
        _setInfo('视频已重新加载');
        return;
      }
      _setBanner('无法重新加载，请重新生成');
      return;
    }

    _reloadingIds.add(item.id);
    clearBannerError();
    _setInfo('正在重新加载视频…');
    _notify();

    final httpClient = http.Client();
    var cancelled = false;
    _manualCancel = false;
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
        _setBanner('无法重新加载，请重新生成');
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
      if (cancelled || _manualCancel) return;

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
        _setInfo('视频已重新加载');
      } else {
        final err = out.errorMessage ?? '重新加载失败，请重新生成';
        await _sessions.markNeedsMaterialize(
          sessionId,
          item.id,
          errorMessage: err,
          remoteVideoUrl: nextRemote.isEmpty ? null : nextRemote,
          jobId: jobId.isNotEmpty ? jobId : null,
        );
        _setBanner(err);
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
      _setBanner(err);
      _logError(err);
    } finally {
      _reloadingIds.remove(item.id);
      generation.end(sessionId, token);
      try {
        httpClient.close();
      } catch (_) {}
      _notify();
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

  /// 用系统播放器打开本地文件或 https URL。
  Future<bool> openVideo(VideoItem item) async {
    final local = item.localPath?.trim();
    if (local != null &&
        local.isNotEmpty &&
        !local.startsWith('http') &&
        !local.startsWith('memory://')) {
      final f = File(local);
      if (await f.exists()) {
        final result = await OpenFilex.open(local);
        if (result.type == ResultType.done) return true;
      }
    }
    final url = (item.videoUrl ?? item.remoteVideoUrl ?? '').trim();
    if (url.startsWith('http')) {
      final uri = Uri.tryParse(url);
      if (uri != null && await canLaunchUrl(uri)) {
        return launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
    if (url.isNotEmpty &&
        !url.startsWith('memory://') &&
        url.contains(RegExp(r'[/\\]'))) {
      final f = File(url);
      if (await f.exists()) {
        final result = await OpenFilex.open(url);
        if (result.type == ResultType.done) return true;
      }
    }
    // memory://：先落临时文件再打开
    if (url.startsWith('memory://') ||
        (local != null && local.startsWith('memory://'))) {
      final bytes = await _resolveBytes(item);
      if (bytes != null && bytes.isNotEmpty) {
        final tmp = await _writeTempMp4(bytes);
        final result = await OpenFilex.open(tmp.path);
        if (result.type == ResultType.done) return true;
      }
    }
    _setBanner('没有可打开的视频文件');
    return false;
  }

  /// 另存到应用文档目录（移动端无系统另存对话框）。
  Future<String?> saveVideoCopy(VideoItem item) async {
    final bytes = await _resolveBytes(item);
    if (bytes == null || bytes.isEmpty) {
      _setBanner('无法读取视频数据');
      return null;
    }
    try {
      final docs = await getApplicationDocumentsDirectory();
      final name =
          'ai-studio-video-${DateTime.now().millisecondsSinceEpoch}.mp4';
      final file = File('${docs.path}${Platform.pathSeparator}$name');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (e) {
      _setBanner(toChatErrorMessage(e, '保存失败'));
      return null;
    }
  }

  Future<File> _writeTempMp4(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}${Platform.pathSeparator}'
      'ai-studio-preview-${DateTime.now().millisecondsSinceEpoch}.mp4',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<Uint8List?> _resolveBytes(VideoItem item) async {
    final local = item.localPath ?? item.videoUrl;
    if (local != null &&
        local.isNotEmpty &&
        !local.startsWith('http') &&
        !local.startsWith('data:')) {
      final fromStore = await _sessions.assetStore.read(local);
      if (fromStore != null) return fromStore;
      if (!local.startsWith('memory://')) {
        final f = File(local);
        if (await f.exists()) return f.readAsBytes();
      }
    }
    final remote = (item.remoteVideoUrl ?? item.videoUrl ?? '').trim();
    if (RegExp(r'^https?://', caseSensitive: false).hasMatch(remote) &&
        !isVideoContentPath(remote)) {
      try {
        final res = await http.get(Uri.parse(remote));
        if (res.statusCode >= 200 && res.statusCode < 300) {
          return res.bodyBytes;
        }
      } catch (_) {}
    }
    return null;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _manualCancel = true;
    final sid = generation.sessionId;
    if (sid != null) {
      generation.abort(sid);
    }
    _modelsCache.dispose();
    if (_ownsClient) _videoClient.close();
    super.dispose();
  }
}

extension _FirstOrNullVideo<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
