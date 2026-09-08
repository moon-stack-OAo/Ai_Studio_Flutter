import 'dart:io';

import 'package:core/core.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

/// Fluent 生视频页状态机（app 层，不进 core）。
class VideoController extends ChangeNotifier {
  VideoController({
    required ProviderRepository providerRepository,
    required VideoSessionRepository sessionRepository,
    required this.generation,
    AppLogRepository? appLogRepository,
    OpenAiCompatibleVideoClient? videoClient,
  })  : _providers = providerRepository,
        _sessions = sessionRepository {
    _facade = VideoJobFacade(
      providers: providerRepository,
      sessions: sessionRepository,
      generation: generation,
      appLogs: appLogRepository,
      videoClient: videoClient,
      onModelsChanged: _notify,
    );
  }

  final ProviderRepository _providers;
  final VideoSessionRepository _sessions;
  final GenerationRuntime generation;
  late final VideoJobFacade _facade;

  String? _bannerError;
  String? _bannerInfo;
  ImageRef? _referenceImage;
  String _refFileName = 'image.png';
  String? _selectedItemId;
  bool _disposed = false;

  static const defaultDurationOptions = VideoJobFacade.defaultDurationOptions;
  static const defaultSizeOptions = VideoJobFacade.defaultSizeOptions;
  static const defaultAspectOptions = VideoJobFacade.defaultAspectOptions;
  static const resolutionOptions = VideoJobFacade.resolutionOptions;

  static const _imageTypeGroup = XTypeGroup(
    label: 'Images',
    extensions: ['png', 'jpg', 'jpeg', 'webp'],
  );

  /// 兼容旧接线。
  static const durationOptions = defaultDurationOptions;
  static const sizeOptions = defaultSizeOptions;
  static const aspectOptions = defaultAspectOptions;

  String? get bannerError => _bannerError;
  String? get bannerInfo => _bannerInfo;
  int get duration => _facade.duration;
  String get size => _facade.size;
  String get aspectRatio => _facade.aspectRatio;
  String get resolution => _facade.resolution;
  String get promptDraft => _facade.promptDraft;
  ImageRef? get referenceImage => _referenceImage;
  bool get hasReferenceImage => _referenceImage != null;
  String? get selectedItemId => _selectedItemId;

  VideoItem? get selectedItem {
    final id = _selectedItemId;
    if (id == null) return null;
    final session = _sessions.activeSession;
    if (session == null) return null;
    for (final item in session.items) {
      if (item.id == id) return item;
    }
    return null;
  }

  VideoSessionRepository get sessions => _sessions;
  ProviderRepository get providers => _providers;
  ProviderModelsCache get modelsCache => _facade.modelsCache;

  bool get isGeneratingActiveSession => _facade.isGeneratingActiveSession;

  bool get canGenerate => _facade.canGenerate;

  bool get isAgnesActive => _facade.isAgnesActive;

  bool get supportsReferenceImage => _facade.supportsReferenceImage;

  bool get isXaiVideoActive => _facade.isXaiVideoActive;

  bool get useAspectRatio => _facade.useAspectRatio;

  bool get useResolution => _facade.useResolution;

  bool get showSize => _facade.showSize;

  List<int> get activeDurationOptions => _facade.activeDurationOptions;

  List<String> get activeSizeOptions => _facade.activeSizeOptions;

  List<String> get activeAspectOptions => _facade.activeAspectOptions;

  bool get hasPendingResume => _facade.hasPendingResume;

  String get promptAssistMode => _facade.promptAssistMode;

  void applyPromptPreset(String prompt) {
    _facade.applyPromptPreset(prompt, onNotify: _notify);
  }

  void setPromptDraft(String value) {
    _facade.setPromptDraft(value, onNotify: _notify);
  }

  /// 通过系统文件选择器加入参考图（图生视频）。
  Future<void> pickReferenceImage() async {
    try {
      final file = await openFile(acceptedTypeGroups: [_imageTypeGroup]);
      if (file == null) return;
      await setReferenceFromPath(file.path, displayName: file.name);
    } catch (_) {
      _setBanner('无法选择参考图');
    }
  }

  /// 拖放文件设为参考图（与点选共用状态）。
  Future<void> dropReferenceImage(String path) async {
    await setReferenceFromPath(path);
  }

  Future<void> setReferenceFromPath(
    String path, {
    String? displayName,
  }) async {
    try {
      final trimmed = path.trim();
      if (trimmed.isEmpty) {
        _setBanner('参考图路径无效');
        return;
      }
      if (!_isAcceptedImagePath(trimmed)) {
        _setBanner('仅支持 PNG / JPEG / WebP 格式');
        return;
      }
      final file = File(trimmed);
      if (!await file.exists()) {
        _setBanner('参考图文件不存在');
        return;
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        _setBanner('参考图读取失败');
        return;
      }
      final name = (displayName ?? _fileNameFromPath(trimmed)).trim();
      _refFileName = name.isEmpty ? 'image.png' : name;
      _referenceImage = ImageRef(type: ImageRefType.file, src: trimmed);
      _facade.setHasReferenceImage(true);
      clearBannerError();
      _notify();
    } catch (_) {
      _setBanner('无法设置参考图');
    }
  }

  void clearReference() {
    if (_referenceImage == null) return;
    _referenceImage = null;
    _refFileName = 'image.png';
    _facade.setHasReferenceImage(false);
    _notify();
  }

  static bool _isAcceptedImagePath(String path) {
    final ext = _extensionOf(path);
    return ext == 'png' || ext == 'jpg' || ext == 'jpeg' || ext == 'webp';
  }

  static String _extensionOf(String path) {
    final name = path.replaceAll('\\', '/').split('/').last;
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  static String _fileNameFromPath(String path) {
    final name = path.replaceAll('\\', '/').split('/').last.trim();
    return name.isEmpty ? 'image.png' : name;
  }

  /// 选中队列项并在右侧播放器展示。
  void selectItem(VideoItem item) {
    if (_selectedItemId == item.id) return;
    _selectedItemId = item.id;
    _notify();
  }

  void clearSelectedItem() {
    if (_selectedItemId == null) return;
    _selectedItemId = null;
    _notify();
  }

  void setDuration(int value) {
    _facade.setDuration(value, onNotify: _notify);
  }

  void setSize(String value) {
    _facade.setSize(value, onNotify: _notify);
  }

  void setAspectRatio(String value) {
    _facade.setAspectRatio(value, onNotify: _notify);
  }

  void setResolution(String value) {
    _facade.setResolution(value, onNotify: _notify);
  }

  /// 切换提供商后校正参数落在可选范围内。
  void syncParamsToActiveProvider() {
    _facade.syncParamsToActiveProvider(onNotify: _notify);
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
    _selectedItemId = null;
    clearBannerError();
  }

  void stop() => _facade.stop();

  /// 启动后静默恢复 pending_resume。
  Future<void> startAutoResumeIfNeeded() {
    return _facade.startAutoResumeIfNeeded(
      onNotify: _notify,
      onBanner: _setBanner,
      onInfo: _setInfo,
    );
  }

  Future<void> resumePending() {
    return _facade.resumePending(
      onNotify: _notify,
      onBanner: _setBanner,
      onInfo: _setInfo,
    );
  }

  Future<void> resumeItem(String sessionId, String itemId) {
    return _facade.resumeItem(
      sessionId,
      itemId,
      onNotify: _notify,
      onBanner: _setBanner,
      onInfo: _setInfo,
    );
  }

  Future<void> abandonItem(String sessionId, String itemId) {
    return _facade.abandonItem(sessionId, itemId, onNotify: _notify);
  }

  Future<void> generate() async {
    if (_disposed) return;
    final text = _facade.promptDraft.trim();

    final refImage = _referenceImage;
    Uint8List? refBytes;
    if (refImage != null) {
      refBytes = await _resolveImageBytes(refImage);
      if (refBytes == null || refBytes.isEmpty) {
        _setBanner('无法读取参考图数据');
        return;
      }
    }
    if ((refBytes == null || refBytes.isEmpty) && text.isEmpty) {
      _setBanner('请输入提示词');
      return;
    }
    if (_providers.activeVideoCredentials == null) {
      _setBanner('请先配置提供商视频模型与 API Key');
      return;
    }
    if (generation.busy) {
      _setBanner('当前有任务进行中，请稍后再试');
      return;
    }

    await _facade.generate(
      prompt: text,
      imageBytes: refBytes,
      imageFileName: _refFileName,
      onNotify: _notify,
      onBanner: _setBanner,
      onInfo: _setInfo,
      bannerOnJobError: false,
    );
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  bool isReloading(String itemId) => _facade.isReloading(itemId);

  /// 重新鉴权拉流 / materialize 落盘。
  Future<void> reloadVideo(VideoItem item) {
    return _facade.reloadVideo(
      item,
      onNotify: _notify,
      onBanner: _setBanner,
      onInfo: _setInfo,
    );
  }

  /// 另存为 mp4；返回是否成功。
  Future<bool> saveVideoAs(VideoItem item) async {
    final bytes = await _facade.resolveVideoBytes(item);
    if (bytes == null || bytes.isEmpty) {
      _setBanner('无法读取视频数据');
      return false;
    }
    final path = await getSaveLocation(
      suggestedName:
          'ai-studio-video-${DateTime.now().millisecondsSinceEpoch}.mp4',
      acceptedTypeGroups: [
        const XTypeGroup(label: 'MP4', extensions: ['mp4']),
      ],
    );
    if (path == null) return false;
    await File(path.path).writeAsBytes(bytes, flush: true);
    return true;
  }

  /// 用系统默认播放器打开本地文件或 https URL。
  Future<bool> openVideo(VideoItem item) async {
    final local = item.localPath?.trim();
    if (local != null &&
        local.isNotEmpty &&
        !local.startsWith('http') &&
        !local.startsWith('memory://')) {
      final f = File(local);
      if (await f.exists()) {
        return _openPath(local);
      }
    }
    final url = (item.videoUrl ?? item.remoteVideoUrl ?? '').trim();
    if (url.startsWith('http')) {
      return _openPath(url);
    }
    if (url.isNotEmpty &&
        !url.startsWith('memory://') &&
        url.contains(RegExp(r'[/\\]'))) {
      final f = File(url);
      if (await f.exists()) {
        return _openPath(url);
      }
    }
    _setBanner('没有可打开的视频文件');
    return false;
  }

  Future<bool> _openPath(String path) async {
    try {
      if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', '', path],
            mode: ProcessStartMode.detached);
        return true;
      }
      if (Platform.isMacOS) {
        await Process.start('open', [path], mode: ProcessStartMode.detached);
        return true;
      }
      if (Platform.isLinux) {
        await Process.start('xdg-open', [path],
            mode: ProcessStartMode.detached);
        return true;
      }
    } catch (e) {
      _setBanner('打开失败：${toChatErrorMessage(e, '无法打开')}');
    }
    return false;
  }

  Future<Uint8List?> _resolveImageBytes(ImageRef ref) async {
    switch (ref.type) {
      case ImageRefType.file:
        final f = File(ref.src);
        if (await f.exists()) return f.readAsBytes();
        return null;
      case ImageRefType.b64:
        return null;
      case ImageRefType.url:
        final client = createSafeHttpClient();
        try {
          final res = await client.get(Uri.parse(ref.src));
          if (res.statusCode >= 200 && res.statusCode < 300) {
            return res.bodyBytes;
          }
        } catch (_) {
        } finally {
          client.close();
        }
        return null;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _facade.dispose();
    super.dispose();
  }
}
