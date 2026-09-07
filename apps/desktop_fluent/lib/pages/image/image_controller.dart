import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../widgets/provider_models_cache.dart';

/// Fluent 生图页状态机（app 层，不进 core）。
class ImageController extends ChangeNotifier {
  ImageController({
    required ProviderRepository providerRepository,
    required ImageSessionRepository sessionRepository,
    required this.generation,
    AppLogRepository? appLogRepository,
    OpenAiCompatibleImageClient? imageClient,
  })  : _providers = providerRepository,
        _sessions = sessionRepository,
        _appLogs = appLogRepository,
        _ownsClient = imageClient == null,
        _imageClient = imageClient ?? OpenAiCompatibleImageClient() {
    _modelsCache = ProviderModelsCache(
      providers: _providers,
      onChanged: notifyListeners,
    );
  }

  final ProviderRepository _providers;
  final ImageSessionRepository _sessions;
  final AppLogRepository? _appLogs;
  final GenerationRuntime generation;
  final OpenAiCompatibleImageClient _imageClient;
  final bool _ownsClient;
  late final ProviderModelsCache _modelsCache;

  String? _bannerError;
  int _n = 1;
  String _size = '1024x1024';
  String _aspectRatio = '1:1';
  String _quality = defaultImageQuality;
  String _promptDraft = '';
  ImageRef? _referenceImage;
  String _refFileName = 'image.png';

  static const sizeOptions = <String>[
    '1024x1024',
    '1024x1792',
    '1792x1024',
  ];

  static const aspectOptions = <String>[
    '1:1',
    '16:9',
    '9:16',
    '4:3',
    '3:4',
  ];

  static const qualityOptions = imageQualityOptions;

  static const _imageTypeGroup = XTypeGroup(
    label: 'Images',
    extensions: ['png', 'jpg', 'jpeg', 'webp'],
  );

  String? get bannerError => _bannerError;
  int get n => _n;
  String get size => _size;
  String get aspectRatio => _aspectRatio;
  String get quality => _quality;
  String get promptDraft => _promptDraft;
  ImageRef? get referenceImage => _referenceImage;
  bool get hasReferenceImage => _referenceImage != null;

  ImageSessionRepository get sessions => _sessions;
  ProviderRepository get providers => _providers;
  ProviderModelsCache get modelsCache => _modelsCache;

  bool get isGeneratingActiveSession =>
      generation.isCurrent(_sessions.activeId);

  bool get canGenerate {
    if (generation.isCurrent(_sessions.activeId)) return false;
    if (!_providers.hasConfiguredImageProvider) return false;
    return _promptDraft.trim().isNotEmpty;
  }

  bool get useAspectRatio {
    final creds = _providers.activeImageCredentials;
    return creds?.type == ProviderType.xai;
  }

  bool get supportsQuality =>
      supportsImageQualityForProvider(_providers.activeProvider);

  String get promptAssistMode =>
      hasReferenceImage ? 'img2img' : 'txt2img';

  void setPromptDraft(String value) {
    if (value == _promptDraft) return;
    _promptDraft = value;
    notifyListeners();
  }

  void setN(int value) {
    final next = value.clamp(1, 4);
    if (next == _n) return;
    _n = next;
    notifyListeners();
  }

  void setSize(String value) {
    if (value == _size) return;
    _size = value;
    notifyListeners();
  }

  void setAspectRatio(String value) {
    if (value == _aspectRatio) return;
    _aspectRatio = value;
    notifyListeners();
  }

  void setQuality(String value) {
    final next = value.trim();
    if (next.isEmpty || next == _quality) return;
    _quality = next;
    notifyListeners();
  }

  void applyPromptPreset(String prompt) {
    final text = prompt.trim();
    if (text.isEmpty) return;
    _promptDraft = text;
    notifyListeners();
  }

  /// 将已生成结果设为参数区参考图。
  void setReferenceFromItem(ImageRef ref) {
    _referenceImage = ref;
    _refFileName = _fileNameFromRef(ref);
    notifyListeners();
  }

  /// 通过系统文件选择器加入参考图。
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
      clearBannerError();
      notifyListeners();
    } catch (_) {
      _setBanner('无法设置参考图');
    }
  }

  void clearReference() {
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

  void _setBanner(String? message) {
    _bannerError = message;
    notifyListeners();
  }

  Future<void> createSession() async {
    await _sessions.createSession();
    clearBannerError();
  }

  Future<void> setActiveSession(String id) async {
    if (id == _sessions.activeId) return;
    await _sessions.setActive(id);
    clearBannerError();
    notifyListeners();
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
    final sid = generation.sessionId;
    if (sid == null) return;
    generation.abort(sid);
  }

  Future<void> generate() async {
    final text = _promptDraft.trim();
    if (text.isEmpty) return;

    final creds = _providers.activeImageCredentials;
    if (creds == null) {
      _setBanner('请先配置提供商生图模型与 API Key');
      return;
    }

    var session = _sessions.activeSession;
    session ??= await _sessions.createSession();
    final sessionId = session.id;

    if (generation.isCurrent(sessionId)) return;

    final refImage = _referenceImage;
    Uint8List? refBytes;
    if (refImage != null) {
      refBytes = await _resolveBytes(refImage);
      if (refBytes == null || refBytes.isEmpty) {
        _setBanner('无法读取参考图数据');
        return;
      }
    }
    final isEdit = refBytes != null && refBytes.isNotEmpty;
    // 仅存短预览标记，避免 dataURL 撑爆存储（core 有 refPreview 上限）。
    final refPreview = isEdit ? 'ref:${refBytes.length}' : null;
    final refFileName = _refFileName;

    clearBannerError();
    _promptDraft = '';
    notifyListeners();

    final qualityParam = supportsQuality ? _quality : null;
    final pending = await _sessions.appendLoadingItem(
      sessionId,
      mode: isEdit ? ImageGenMode.edit : ImageGenMode.text,
      prompt: text,
      model: creds.imageModel,
      providerName: creds.providerName,
      n: _n,
      size: useAspectRatio ? null : _size,
      aspectRatio: useAspectRatio ? _aspectRatio : null,
      quality: qualityParam,
      refPreview: refPreview,
    );
    if (pending == null) return;

    final httpClient = http.Client();
    final token = generation.begin(sessionId, httpClient.close);
    notifyListeners();

    try {
      final List<ImageRef> refs;
      if (isEdit) {
        refs = await _imageClient.editImage(
          baseUrl: creds.baseUrl,
          apiKey: creds.apiKey,
          model: creds.imageModel,
          providerType: creds.type,
          prompt: text,
          imageBytes: refBytes,
          imageFileName: refFileName,
          n: _n,
          size: useAspectRatio ? null : _size,
          aspectRatio: useAspectRatio ? _aspectRatio : null,
          quality: qualityParam,
          client: httpClient,
        );
      } else {
        refs = await _imageClient.generateTextToImageWithCredentials(
          creds,
          prompt: text,
          n: _n,
          size: useAspectRatio ? null : _size,
          aspectRatio: useAspectRatio ? _aspectRatio : null,
          quality: qualityParam,
          client: httpClient,
        );
      }
      await _sessions.completeItem(sessionId, pending.id, refs);
    } on ChatAbortException {
      await _sessions.failItem(sessionId, pending.id, '已取消');
    } catch (e) {
      if (isAbortLike(e)) {
        await _sessions.failItem(sessionId, pending.id, '已取消');
      } else {
        final msg = toChatErrorMessage(e, '生成失败');
        await _sessions.failItem(sessionId, pending.id, msg);
        final logs = _appLogs;
        if (logs != null) {
          unawaited(
            logs.append(
              level: AppLogLevel.error,
              source: AppLogSources.image,
              message: msg,
            ),
          );
        }
      }
    } finally {
      generation.end(sessionId, token);
      try {
        httpClient.close();
      } catch (_) {}
      notifyListeners();
    }
  }

  /// 另存为 PNG；返回是否成功。
  Future<bool> saveImageAs(ImageRef ref) async {
    final bytes = await _resolveBytes(ref);
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

  Future<Uint8List?> _resolveBytes(ImageRef ref) async {
    switch (ref.type) {
      case ImageRefType.file:
      case ImageRefType.b64:
        return _sessions.readImageBytes(ref);
      case ImageRefType.url:
        try {
          final res = await http.get(Uri.parse(ref.src));
          if (res.statusCode >= 200 && res.statusCode < 300) {
            return res.bodyBytes;
          }
        } catch (_) {}
        return null;
    }
  }

  @override
  void dispose() {
    _modelsCache.dispose();
    if (_ownsClient) _imageClient.close();
    super.dispose();
  }
}
