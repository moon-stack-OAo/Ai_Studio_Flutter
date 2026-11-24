import 'dart:io';

import 'package:core/core.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

/// Fluent 生图页薄包装：平台 IO + [ImageSessionFacade]。
class ImageController extends ChangeNotifier {
  ImageController({
    required ProviderRepository providerRepository,
    required ImageSessionRepository sessionRepository,
    required this.generation,
    Future<Uint8List?> Function(ImageRef)? readDraftReference,
    AppLogRepository? appLogRepository,
    OpenAiCompatibleImageClient? imageClient,
    SkillRepository? skillRepository,
  }) : _providers = providerRepository,
       _sessions = sessionRepository {
    _draftGuard = MediaDraftRestoreGuard([
      providerRepository,
      sessionRepository,
      generation,
    ]);
    _readDraftReference = readDraftReference ?? readLocalMediaDraftReference;
    _facade = ImageSessionFacade(
      skillRepository: skillRepository,
      providers: providerRepository,
      sessions: sessionRepository,
      generation: generation,
      appLogs: appLogRepository,
      imageClient: imageClient,
      onModelsChanged: notifyListeners,
    );
  }

  final ProviderRepository _providers;
  final ImageSessionRepository _sessions;
  final GenerationRuntime generation;
  late final ImageSessionFacade _facade;

  String? _bannerError;
  String? _bannerInfo;
  ImageRef? _referenceImage;
  String _refFileName = 'image.png';
  bool _disposed = false;
  late final MediaDraftRestoreGuard _draftGuard;
  late final Future<Uint8List?> Function(ImageRef) _readDraftReference;

  static const sizeOptions = ImageSessionFacade.sizeOptions;
  static const aspectOptions = ImageSessionFacade.aspectOptions;
  static const qualityOptions = ImageSessionFacade.qualityOptions;

  static const _imageTypeGroup = XTypeGroup(
    label: 'Images',
    extensions: ['png', 'jpg', 'jpeg', 'webp'],
  );

  String? get bannerError => _bannerError;
  String? get bannerInfo => _bannerInfo;
  int get n => _facade.n;
  String get size => _facade.size;
  String get aspectRatio => _facade.aspectRatio;
  String get quality => _facade.quality;
  String get promptDraft => _facade.promptDraft;
  ImageRef? get referenceImage => _referenceImage;
  bool get hasReferenceImage => _referenceImage != null;

  ImageSessionRepository get sessions => _sessions;
  ProviderRepository get providers => _providers;
  ProviderModelsCache get modelsCache => _facade.modelsCache;

  bool get isGeneratingActiveSession => _facade.isGeneratingActiveSession;

  bool get canGenerate => _facade.canGenerate;

  bool get useAspectRatio => _facade.useAspectRatio;

  bool get showSize => _facade.showSize;

  List<String> get activeSizeOptions => _facade.activeSizeOptions;

  List<String> get activeAspectOptions => _facade.activeAspectOptions;

  bool get supportsQuality => _facade.supportsQuality;

  void syncParamsToActiveProvider() {
    _draftGuard.invalidate();
    _facade.syncParamsToActiveProvider(onNotify: notifyListeners);
  }

  String get promptAssistMode => hasReferenceImage ? 'img2img' : 'txt2img';

  void setPromptDraft(String value) {
    _draftGuard.invalidate();
    _facade.setPromptDraft(value, onNotify: notifyListeners);
  }

  void setN(int value) {
    _draftGuard.invalidate();
    _facade.setN(value, onNotify: notifyListeners);
  }

  void setSize(String value) {
    _draftGuard.invalidate();
    _facade.setSize(value, onNotify: notifyListeners);
  }

  void setAspectRatio(String value) {
    _draftGuard.invalidate();
    _facade.setAspectRatio(value, onNotify: notifyListeners);
  }

  void setQuality(String value) {
    _draftGuard.invalidate();
    _facade.setQuality(value, onNotify: notifyListeners);
  }

  void applyPromptPreset(String prompt) {
    _draftGuard.invalidate();
    _facade.applyPromptPreset(prompt, onNotify: notifyListeners);
  }

  /// `IMG-RERUN`：回填提示词 / 参数 / 参考图到 Composer，不自动提交。
  Future<void> rerunFromItem(ImageItem item) async {
    if (_disposed) return;
    if (generation.busy) {
      _setBanner('当前有任务进行中，请稍后再试');
      return;
    }

    final ticket = _draftGuard.begin();
    final reference = await selectMediaDraftReference(
      item.referenceImages,
      read: _readDraftReference,
      isCurrent: () => _draftGuard.isCurrent(ticket) && !generation.busy,
    );
    if (!_draftGuard.isCurrent(ticket) || generation.busy || _disposed) return;
    _facade.restoreDraftFromItem(item);
    _referenceImage = reference?.ref;
    _refFileName = reference?.fileName ?? 'image.png';
    _bannerError = null;
    _bannerInfo = reference == null && item.referenceImages.isNotEmpty
        ? '原参考图不可用，已仅回填提示词与参数'
        : null;
    notifyListeners();
  }

  /// 将已生成结果设为参数区参考图。
  void setReferenceFromItem(ImageRef ref) {
    _draftGuard.invalidate();
    _referenceImage = ref;
    _refFileName = _fileNameFromRef(ref);
    notifyListeners();
  }

  /// 通过系统文件选择器加入参考图。
  Future<void> pickReferenceImage() async {
    _draftGuard.invalidate();
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

  Future<void> setReferenceFromPath(String path, {String? displayName}) async {
    _draftGuard.invalidate();
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
      clearBannerError();
      notifyListeners();
    } catch (_) {
      _setBanner('无法设置参考图');
    }
  }

  void clearReference() {
    _draftGuard.invalidate();
    if (_referenceImage == null) return;
    _referenceImage = null;
    _refFileName = 'image.png';
    notifyListeners();
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

  String _fileNameFromRef(ImageRef ref) {
    if (ref.type == ImageRefType.file) {
      final name = ref.src.replaceAll('\\', '/').split('/').last.trim();
      if (name.isNotEmpty) return name;
    }
    return 'image.png';
  }

  void clearBannerError() {
    if (_bannerError == null) return;
    _bannerError = null;
    notifyListeners();
  }

  void clearBannerInfo() {
    if (_bannerInfo == null) return;
    _bannerInfo = null;
    notifyListeners();
  }

  void _setBanner(String? message) {
    if (message == null) {
      clearBannerError();
      return;
    }
    _bannerError = message;
    notifyListeners();
  }

  Future<void> createSession() async {
    _draftGuard.invalidate();
    await _sessions.createSession();
    clearBannerError();
  }

  Future<void> setActiveSession(String id) async {
    _draftGuard.invalidate();
    if (id == _sessions.activeId) return;
    await _sessions.setActive(id);
    clearBannerError();
    notifyListeners();
  }

  Future<void> removeSession(String id) async {
    _draftGuard.invalidate();
    generation.abortIfSession(id);
    await _sessions.removeSession(id);
    clearBannerError();
  }

  Future<void> clearActiveItems() async {
    _draftGuard.invalidate();
    final sid = _sessions.activeId;
    if (sid.isEmpty) return;
    if (generation.isCurrent(sid)) {
      generation.abort(sid);
    }
    await _sessions.clearItems(sid);
    clearBannerError();
  }

  void stop() => _facade.stop();

  Future<void> generate() async {
    _draftGuard.invalidate();
    final refImage = _referenceImage;
    Uint8List? refBytes;
    if (refImage != null) {
      refBytes = await _facade.resolveImageBytes(refImage);
      if (refBytes == null || refBytes.isEmpty) {
        _setBanner('无法读取参考图数据');
        return;
      }
    }

    await _facade.generate(
      imageBytes: refBytes,
      imageFileName: _refFileName,
      onNotify: notifyListeners,
      onBanner: _setBanner,
      bannerOnGenerateError: false,
    );
  }

  /// 另存为 PNG；返回是否成功。
  Future<bool> saveImageAs(ImageRef ref) async {
    final bytes = await _facade.resolveImageBytes(ref);
    if (bytes == null || bytes.isEmpty) {
      _setBanner('无法读取图片数据');
      return false;
    }
    final path = await getSaveLocation(
      suggestedName: 'ai-studio-${DateTime.now().millisecondsSinceEpoch}.png',
      acceptedTypeGroups: [
        const XTypeGroup(label: 'PNG', extensions: ['png']),
      ],
    );
    if (path == null) return false;
    await File(path.path).writeAsBytes(bytes, flush: true);
    return true;
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _draftGuard.dispose();
    _facade.dispose();
    super.dispose();
  }
}
