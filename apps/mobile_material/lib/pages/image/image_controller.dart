import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// Material 生图页薄包装：平台 IO + [ImageSessionFacade]。
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
        _picker = imagePicker ?? ImagePicker() {
    _facade = ImageSessionFacade(
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
  final ImagePicker _picker;
  late final ImageSessionFacade _facade;

  String? _bannerError;
  Uint8List? _refBytes;
  String _refFileName = 'image.png';

  static const sizeOptions = ImageSessionFacade.sizeOptions;
  static const aspectOptions = ImageSessionFacade.aspectOptions;
  static const qualityOptions = ImageSessionFacade.qualityOptions;

  String? get bannerError => _bannerError;
  int get n => _facade.n;
  String get size => _facade.size;
  String get aspectRatio => _facade.aspectRatio;
  String get quality => _facade.quality;
  String get promptDraft => _facade.promptDraft;
  Uint8List? get refBytes => _refBytes;
  bool get hasRefImage => _refBytes != null && _refBytes!.isNotEmpty;

  ImageSessionRepository get sessions => _sessions;
  ProviderRepository get providers => _providers;
  ProviderModelsCache get modelsCache => _facade.modelsCache;

  bool get isGeneratingActiveSession => _facade.isGeneratingActiveSession;

  bool get canGenerate => _facade.canGenerate;

  bool get useAspectRatio => _facade.useAspectRatio;

  bool get supportsQuality => _facade.supportsQuality;

  String get promptAssistMode => hasRefImage ? 'img2img' : 'txt2img';

  void setPromptDraft(String value) {
    _facade.setPromptDraft(value, onNotify: notifyListeners);
  }

  void setN(int value) {
    _facade.setN(value, onNotify: notifyListeners);
  }

  void setSize(String value) {
    _facade.setSize(value, onNotify: notifyListeners);
  }

  void setAspectRatio(String value) {
    _facade.setAspectRatio(value, onNotify: notifyListeners);
  }

  void setQuality(String value) {
    _facade.setQuality(value, onNotify: notifyListeners);
  }

  void applyPromptPreset(String prompt) {
    _facade.applyPromptPreset(prompt, onNotify: notifyListeners);
  }

  /// 将已生成结果设为参数区参考图。
  Future<void> setReferenceFromItem(ImageRef ref) async {
    final bytes = await _facade.resolveImageBytes(ref);
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

  void clearBannerError() {
    if (_bannerError == null) return;
    _bannerError = null;
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

  void stop() => _facade.stop();

  Future<void> generate() async {
    await _facade.generate(
      imageBytes: _refBytes,
      imageFileName: _refFileName,
      onNotify: notifyListeners,
      onBanner: _setBanner,
      bannerOnGenerateError: true,
    );
  }

  @override
  void dispose() {
    _facade.dispose();
    super.dispose();
  }
}
