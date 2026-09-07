import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../widgets/provider_models_cache.dart';

/// Material 生图页状态机（app 层，不进 core）。
class ImageController extends ChangeNotifier {
  ImageController({
    required ProviderRepository providerRepository,
    required ImageSessionRepository sessionRepository,
    required this.generation,
    AppLogRepository? appLogRepository,
    OpenAiCompatibleImageClient? imageClient,
    ImagePicker? imagePicker,
  })  : _providers = providerRepository,
        _sessions = sessionRepository,
        _appLogs = appLogRepository,
        _ownsClient = imageClient == null,
        _imageClient = imageClient ?? OpenAiCompatibleImageClient(),
        _picker = imagePicker ?? ImagePicker() {
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
  final ImagePicker _picker;
  late final ProviderModelsCache _modelsCache;

  String? _bannerError;
  int _n = 1;
  String _size = '1024x1024';
  String _aspectRatio = '1:1';
  String _quality = defaultImageQuality;
  String _promptDraft = '';
  Uint8List? _refBytes;
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

  String? get bannerError => _bannerError;
  int get n => _n;
  String get size => _size;
  String get aspectRatio => _aspectRatio;
  String get quality => _quality;
  String get promptDraft => _promptDraft;
  Uint8List? get refBytes => _refBytes;
  bool get hasRefImage => _refBytes != null && _refBytes!.isNotEmpty;

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

  String get promptAssistMode => hasRefImage ? 'img2img' : 'txt2img';

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
  Future<void> setReferenceFromItem(ImageRef ref) async {
    final bytes = await _resolveBytes(ref);
    if (bytes == null || bytes.isEmpty) {
      _setBanner('无法读取参考图数据');
      return;
    }
    _refBytes = bytes;
    _refFileName = _fileNameFromRef(ref);
    clearBannerError();
    notifyListeners();
  }

  String _fileNameFromRef(ImageRef ref) {
    if (ref.type == ImageRefType.file) {
      final name = ref.src.replaceAll('\\', '/').split('/').last.trim();
      if (name.isNotEmpty) return name;
    }
    return 'image.png';
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

  void clearBannerError() {
    if (_bannerError == null) return;
    _bannerError = null;
    notifyListeners();
  }

  void _setBanner(String? message) {
    _bannerError = message;
    notifyListeners();
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
      notifyListeners();
    } catch (_) {
      _setBanner('无法选择参考图');
    }
  }

  void clearRefImage() {
    if (_refBytes == null) return;
    _refBytes = null;
    _refFileName = 'image.png';
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

    final ref = _refBytes;
    final isEdit = ref != null && ref.isNotEmpty;
    // 仅存短预览标记，避免 dataURL 撑爆存储（core 有 refPreview 上限）。
    final refPreview = isEdit ? 'ref:${ref.length}' : null;

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
          imageBytes: ref,
          imageFileName: _refFileName,
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
        _setBanner(msg);
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

  @override
  void dispose() {
    _modelsCache.dispose();
    if (_ownsClient) _imageClient.close();
    super.dispose();
  }
}
