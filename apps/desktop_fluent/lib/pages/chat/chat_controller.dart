import 'dart:io';

import 'package:core/core.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

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

/// Fluent 对话页薄包装：UI 状态 + [ChatSessionFacade]。
class ChatController extends ChangeNotifier {
  ChatController({
    required ProviderRepository providerRepository,
    required ChatSessionRepository sessionRepository,
    required ChatDefaultsRepository chatDefaultsRepository,
    required this.generation,
    AppLogRepository? appLogRepository,
    OpenAiCompatibleChatClient? chatClient,
    McpServerRepository? mcpServerRepository,
    McpSessionFactory? mcpSessionFactory,
    Future<bool> Function(ToolAuthPrompt prompt)? toolAuthPrompter,
  })  : _providers = providerRepository,
        _sessions = sessionRepository,
        _mcpServers = mcpServerRepository {
    _facade = ChatSessionFacade(
      providers: providerRepository,
      sessions: sessionRepository,
      chatDefaults: chatDefaultsRepository,
      generation: generation,
      appLogs: appLogRepository,
      chatClient: chatClient,
      onModelsChanged: notifyListeners,
      mcpServers: mcpServerRepository,
      mcpSessionFactory: mcpSessionFactory,
      toolAuthPrompter: toolAuthPrompter ?? _defaultDenyAuth,
      onToolTrace: _onToolTrace,
    );
    _mcpServers?.addListener(_onMcpChanged);
  }

  final ProviderRepository _providers;
  final ChatSessionRepository _sessions;
  final McpServerRepository? _mcpServers;
  final GenerationRuntime generation;
  late final ChatSessionFacade _facade;

  String? _bannerError;
  final List<ChatDraftAttachment> _draftAttachments = [];
  final Map<String, ChatToolCallTrace> _liveTraces = {};

  static const _imageTypeGroup = XTypeGroup(
    label: 'Images',
    extensions: ['png', 'jpg', 'jpeg', 'webp'],
  );

  static Future<bool> _defaultDenyAuth(ToolAuthPrompt prompt) async => false;

  String? get bannerError => _bannerError;

  ChatSessionRepository get sessions => _sessions;

  ProviderRepository get providers => _providers;

  McpServerRepository? get mcpServers => _mcpServers;

  /// 当前发送回合的 live 工具轨迹（CHAT-TOOL-CALL）。
  List<ChatToolCallTrace> get liveToolTraces {
    final list = _liveTraces.values.toList(growable: false);
    list.sort((a, b) => a.toolCallId.compareTo(b.toolCallId));
    return list;
  }

  bool get hasLiveToolTraces => _liveTraces.isNotEmpty;

  List<ChatDraftAttachment> get draftAttachments =>
      List.unmodifiable(_draftAttachments);

  bool get hasDraftAttachments => _draftAttachments.isNotEmpty;

  int get draftAttachmentCount => _draftAttachments.length;

  bool get canAddMoreAttachments =>
      _draftAttachments.length < maxChatAttachments;

  bool get activeChatSupportsVision => _facade.activeChatSupportsVision;

  bool get activeChatSupportsTools => _facade.activeChatSupportsTools;

  bool get isMcpWiringEnabled => _facade.isMcpWiringEnabled;

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

  void _onMcpChanged() {
    notifyListeners();
  }

  void _onToolTrace(ChatToolCallTrace trace) {
    _liveTraces[trace.toolCallId] = trace;
    notifyListeners();
  }

  void clearLiveToolTraces() {
    if (_liveTraces.isEmpty) return;
    _liveTraces.clear();
    notifyListeners();
  }

  Future<void> createSession() async {
    await _sessions.createSession();
    clearBannerError();
    clearLiveToolTraces();
  }

  Future<void> setActiveSession(String id) async {
    if (id == _sessions.activeId) return;
    await _sessions.setActive(id);
    clearBannerError();
    clearLiveToolTraces();
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

  Future<void> recallLastUser() async {
    if (isStreamingActiveSession) return;
    final session = _sessions.activeSession;
    if (session == null) return;
    await _sessions.recallUserMessage(session.id);
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

  /// 系统文件选择器追加附图（最多补满 [maxChatAttachments]）。
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
      final files = await openFiles(acceptedTypeGroups: [_imageTypeGroup]);
      if (files.isEmpty) return;
      for (final file in files) {
        if (!canAddMoreAttachments) {
          _setBanner('每条消息最多附加 $maxChatAttachments 张图片');
          break;
        }
        await _addAttachmentFromPath(file.path, displayName: file.name);
      }
    } catch (_) {
      _setBanner('无法选择图片');
    }
  }

  /// 拖放路径追加一张附图。
  Future<void> dropAttachment(String path) async {
    if (!activeChatSupportsVision) {
      _setBanner('当前模型不支持图片，请更换支持视觉的对话模型');
      return;
    }
    if (!canAddMoreAttachments) {
      _setBanner('每条消息最多附加 $maxChatAttachments 张图片');
      return;
    }
    await _addAttachmentFromPath(path);
  }

  Future<void> _addAttachmentFromPath(
    String path, {
    String? displayName,
  }) async {
    try {
      final trimmed = path.trim();
      if (trimmed.isEmpty) {
        _setBanner('图片路径无效');
        return;
      }
      if (!_isAcceptedImagePath(trimmed)) {
        _setBanner('仅支持 PNG / JPEG / WebP 图片');
        return;
      }
      final file = File(trimmed);
      if (!await file.exists()) {
        _setBanner('图片文件不存在');
        return;
      }
      final bytes = await file.readAsBytes();
      final mimeHint = _mimeFromPath(trimmed);
      final err = validateChatAttachmentBytes(bytes, mime: mimeHint);
      if (err != null) {
        _setBanner(err);
        return;
      }
      final resolved = resolveChatAttachmentMime(bytes, mimeHint);
      final name = (displayName ?? _fileNameFromPath(trimmed)).trim();
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
    clearLiveToolTraces();
    await _facade.send(
      raw,
      onNotify: notifyListeners,
      onBanner: _setBanner,
      bannerOnStreamError: false,
      attachmentBytes: bytes.isEmpty ? null : bytes,
      attachmentMimes: mimes.isEmpty ? null : mimes,
    );
  }

  static bool _isAcceptedImagePath(String path) {
    final ext = _extensionOf(path);
    return ext == 'png' || ext == 'jpg' || ext == 'jpeg' || ext == 'webp';
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

  static String _fileNameFromPath(String path) {
    final name = path.replaceAll('\\', '/').split('/').last.trim();
    return name.isEmpty ? 'image.png' : name;
  }

  @override
  void dispose() {
    _mcpServers?.removeListener(_onMcpChanged);
    _facade.dispose();
    super.dispose();
  }
}
