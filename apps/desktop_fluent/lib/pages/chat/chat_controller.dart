import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

/// Fluent 对话页薄包装：UI 状态 + [ChatSessionFacade]。
class ChatController extends ChangeNotifier {
  ChatController({
    required ProviderRepository providerRepository,
    required ChatSessionRepository sessionRepository,
    required ChatDefaultsRepository chatDefaultsRepository,
    required this.generation,
    AppLogRepository? appLogRepository,
    OpenAiCompatibleChatClient? chatClient,
  })  : _providers = providerRepository,
        _sessions = sessionRepository {
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
  late final ChatSessionFacade _facade;

  String? _bannerError;

  String? get bannerError => _bannerError;

  ChatSessionRepository get sessions => _sessions;

  ProviderRepository get providers => _providers;

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

  Future<void> send(String raw) {
    return _facade.send(
      raw,
      onNotify: notifyListeners,
      onBanner: _setBanner,
      bannerOnStreamError: false,
    );
  }

  @override
  void dispose() {
    _facade.dispose();
    super.dispose();
  }
}
