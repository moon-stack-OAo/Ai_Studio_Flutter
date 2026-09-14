import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// Composer 草稿附图（尚未落盘；发送时交给 facade）。
class ChatDraftAttachment {
  const ChatDraftAttachment({
    required this.bytes,
    required this.name,
    this.mime,
  });

  final Uint8List bytes;
  final String name;
  final String? mime;
}

/// Material 对话页薄包装：UI 状态 + [ChatSessionFacade]。
class ChatController extends ChangeNotifier {
  ChatController({
    required ProviderRepository providerRepository,
    required ChatSessionRepository sessionRepository,
    required ChatDefaultsRepository chatDefaultsRepository,
    required this.generation,
    AppLogRepository? appLogRepository,
    OpenAiCompatibleChatClient? chatClient,
    ImagePicker? imagePicker,
  })  : _providers = providerRepository,
        _sessions = sessionRepository,
        _picker = imagePicker ?? ImagePicker() {
    _facade = ChatSessionFacade(
      providers: providerRepository,
      sessions: sessionRepository,
      chatDefaults: chatDefaultsRepository,
      generation: generation,
      appLogs: appLogRepository,
      chatClient: chatClient,
      onModelsChanged: notifyListeners,
    );
  }

  final ProviderRepository _providers;
  final ChatSessionRepository _sessions;
  final GenerationRuntime generation;
  final ImagePicker _picker;
  late final ChatSessionFacade _facade;

  String? _bannerError;
  final List<ChatDraftAttachment> _draftAttachments = [];

  String? get bannerError => _bannerError;

  ChatSessionRepository get sessions => _sessions;

  ProviderRepository get providers => _providers;

  List<ChatDraftAttachment> get draftAttachments =>
      List<ChatDraftAttachment>.unmodifiable(_draftAttachments);

  bool get hasDraftAttachments => _draftAttachments.isNotEmpty;

  int get draftAttachmentCount => _draftAttachments.length;

  bool get canAddMoreAttachments =>
      _draftAttachments.length < maxChatAttachments;

  bool get activeChatSupportsVision => _facade.activeChatSupportsVision;

  bool get modelsLoading => _facade.modelsCache.loading;

  String? get modelsError => _facade.modelsCache.error;

  List<ProviderModelInfo> get cachedChatModels =>
      _facade.modelsCache.cachedForActive;

  bool get hasCachedChatModels => _facade.modelsCache.hasCached;

  bool get isChatModelsCacheFresh => _facade.modelsCache.isFresh;

  Future<List<ProviderModelInfo>> loadChatModels({
    bool force = false,
    bool silentRefreshIfStale = true,
  }) {
    return _facade.loadChatModels(
      force: force,
      silentRefreshIfStale: silentRefreshIfStale,
    );
  }

  bool get isStreamingActiveSession => _facade.isStreamingActiveSession;

  bool get canSend => _facade.canSend;

  bool canSendWith({String textDraft = ''}) {
    return _facade.canSendWith(
      textDraft: textDraft,
      hasAttachments: hasDraftAttachments,
    );
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

  Future<void> renameSession(String id, String title) async {
    await _sessions.renameSession(id, title);
  }

  Future<void> setSessionOverrides(ChatOverrides overrides) async {
    final session = _sessions.activeSession;
    if (session == null) return;
    await _sessions.setSessionOverrides(session.id, overrides);
  }

  Future<void> recallUserMessage(String userMessageId) async {
    if (isStreamingActiveSession) return;
    final session = _sessions.activeSession;
    if (session == null) return;
    await _sessions.recallUserMessage(
      session.id,
      userMessageId: userMessageId,
    );
  }

  void stop() => _facade.stop();

  /// 相册多选追加附图（最多补满 [maxChatAttachments]）。
  Future<void> pickAttachments() async {
    if (!activeChatSupportsVision) {
      _setBanner('当前模型不支持图片，请更换支持视觉的对话模型');
      return;
    }
    if (!canAddMoreAttachments) {
      _setBanner('每条消息最多附加 $maxChatAttachments 张图片');
      return;
    }
    try {
      final remaining = maxChatAttachments - _draftAttachments.length;
      final files = await _picker.pickMultiImage(
        imageQuality: 95,
        limit: remaining,
      );
      if (files.isEmpty) return;
      for (final file in files) {
        if (!canAddMoreAttachments) {
          _setBanner('每条消息最多附加 $maxChatAttachments 张图片');
          break;
        }
        await _addAttachmentFromXFile(file);
      }
    } catch (_) {
      _setBanner('无法选择图片');
    }
  }

  Future<void> _addAttachmentFromXFile(XFile file) async {
    try {
      final bytes = await file.readAsBytes();
      final mimeHint = _mimeFromXFile(file);
      final err = validateChatAttachmentBytes(bytes, mime: mimeHint);
      if (err != null) {
        _setBanner(err);
        return;
      }
      final resolved = resolveChatAttachmentMime(bytes, mimeHint);
      final name = file.name.trim();
      _draftAttachments.add(
        ChatDraftAttachment(
          bytes: bytes,
          name: name.isEmpty ? 'image.png' : name,
          mime: resolved,
        ),
      );
      clearBannerError();
      notifyListeners();
    } catch (_) {
      _setBanner('无法添加图片');
    }
  }

  void removeDraftAttachmentAt(int index) {
    if (index < 0 || index >= _draftAttachments.length) return;
    _draftAttachments.removeAt(index);
    notifyListeners();
  }

  void clearDraftAttachments() {
    if (_draftAttachments.isEmpty) return;
    _draftAttachments.clear();
    notifyListeners();
  }

  Future<void> send(String raw) async {
    final drafts = List<ChatDraftAttachment>.from(_draftAttachments);
    if (raw.trim().isEmpty && drafts.isEmpty) return;
    if (!canSendWith(textDraft: raw)) return;
    if (drafts.isNotEmpty && !activeChatSupportsVision) {
      _setBanner('当前模型不支持图片，请更换支持视觉的对话模型');
      return;
    }
    final bytes = drafts.map((d) => d.bytes).toList(growable: false);
    final mimes = drafts.map((d) => d.mime).toList(growable: false);
    if (drafts.isNotEmpty) {
      _draftAttachments.clear();
      notifyListeners();
    }
    await _facade.send(
      raw,
      onNotify: notifyListeners,
      onBanner: _setBanner,
      bannerOnStreamError: true,
      attachmentBytes: bytes.isEmpty ? null : bytes,
      attachmentMimes: mimes.isEmpty ? null : mimes,
    );
  }

  static String? _mimeFromXFile(XFile file) {
    final declared = file.mimeType?.trim();
    if (declared != null && declared.isNotEmpty) return declared;
    return _mimeFromPath(file.name.isNotEmpty ? file.name : file.path);
  }

  static String? _mimeFromPath(String path) {
    switch (_extensionOf(path)) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      default:
        return null;
    }
  }

  static String _extensionOf(String path) {
    final name = path.replaceAll('\\', '/').split('/').last;
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  @override
  void dispose() {
    _facade.dispose();
    super.dispose();
  }
}
