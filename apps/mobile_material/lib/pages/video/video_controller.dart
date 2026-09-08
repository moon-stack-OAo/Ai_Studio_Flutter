import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

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
        _picker = imagePicker ?? ImagePicker() {
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
  final ImagePicker _picker;
  late final VideoJobFacade _facade;

  String? _bannerError;
  String? _bannerInfo;
  Uint8List? _refBytes;
  String _refFileName = 'image.png';
  bool _disposed = false;

  static const defaultDurationOptions = VideoJobFacade.defaultDurationOptions;
  static const defaultSizeOptions = VideoJobFacade.defaultSizeOptions;
  static const defaultAspectOptions = VideoJobFacade.defaultAspectOptions;
  static const resolutionOptions = VideoJobFacade.resolutionOptions;

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
  Uint8List? get refBytes => _refBytes;
  bool get hasRefImage => _refBytes != null && _refBytes!.isNotEmpty;

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
      _facade.setHasReferenceImage(true);
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
    _facade.setHasReferenceImage(false);
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
    clearBannerError();
  }

  void stop() => _facade.stop();

  /// 进入页后静默恢复 pending_resume。
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
    final ref = _refBytes;
    final hasRef = ref != null && ref.isNotEmpty;
    if (!hasRef && text.isEmpty) {
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
      imageBytes: ref,
      imageFileName: _refFileName,
      onNotify: _notify,
      onBanner: _setBanner,
      onInfo: _setInfo,
      bannerOnJobError: true,
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
      final bytes = await _facade.resolveVideoBytes(item);
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
    final bytes = await _facade.resolveVideoBytes(item);
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

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _facade.dispose();
    super.dispose();
  }
}
