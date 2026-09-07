import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Fluent 对话页发送 / 停止状态机（app 层，不进 core）。
class ChatController extends ChangeNotifier {
  ChatController({
    required ProviderRepository providerRepository,
    required ChatSessionRepository sessionRepository,
    required ChatDefaultsRepository chatDefaultsRepository,
    required this.generation,
    AppLogRepository? appLogRepository,
    OpenAiCompatibleChatClient? chatClient,
  })  : _providers = providerRepository,
        _sessions = sessionRepository,
        _chatDefaults = chatDefaultsRepository,
        _appLogs = appLogRepository,
        _ownsClient = chatClient == null,
        _chatClient = chatClient ?? OpenAiCompatibleChatClient();

  final ProviderRepository _providers;
  final ChatSessionRepository _sessions;
  final ChatDefaultsRepository _chatDefaults;
  final AppLogRepository? _appLogs;
  final GenerationRuntime generation;
  final OpenAiCompatibleChatClient _chatClient;
  final bool _ownsClient;

  static const Duration modelCacheTtl = Duration(minutes: 5);

  String? _bannerError;
  String? _streamingAssistantId;
  DateTime? _lastPersistAt;

  /// 按 providerId 缓存的对话模型列表（CHAT-MODEL Combo）。
  final Map<String, List<ProviderModelInfo>> _modelsCache = {};
  final Map<String, DateTime> _modelsCacheAt = {};
  bool _modelsLoading = false;
  String? _modelsError;

  String? get bannerError => _bannerError;

  ChatSessionRepository get sessions => _sessions;

  ProviderRepository get providers => _providers;

  bool get modelsLoading => _modelsLoading;

  String? get modelsError => _modelsError;

  /// 当前激活提供商的缓存模型（无缓存返回空列表）。
  List<ProviderModelInfo> get cachedChatModels {
    final id = _providers.activeProvider?.id;
    if (id == null) return const [];
    return List.unmodifiable(_modelsCache[id] ?? const []);
  }

  bool get hasCachedChatModels => cachedChatModels.isNotEmpty;

  /// 当前激活提供商的模型缓存是否仍在 TTL 内。
  bool get isChatModelsCacheFresh {
    final id = _providers.activeProvider?.id;
    if (id == null) return false;
    return _cacheFresh(id);
  }

  bool _cacheFresh(String providerId) {
    final at = _modelsCacheAt[providerId];
    if (at == null) return false;
    return DateTime.now().difference(at) < modelCacheTtl;
  }

  bool _sameModelIds(
    List<ProviderModelInfo>? a,
    List<ProviderModelInfo> b,
  ) {
    if (a == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  /// 拉取对话模型列表。
  ///
  /// [force] 为 true 时强制刷新；否则有缓存则直接返回，TTL 过期可静默刷新。
  /// 失败时保留旧缓存（若有）。
  /// 静默刷新不切换 [modelsLoading]，且仅在列表变化时 [notifyListeners]。
  Future<List<ProviderModelInfo>> loadChatModels({
    bool force = false,
    bool silentRefreshIfStale = true,
  }) async {
    final p = _providers.activeProvider;
    if (p == null || !p.canChat) {
      return const [];
    }
    final cached = _modelsCache[p.id];
    if (!force && cached != null && cached.isNotEmpty) {
      if (silentRefreshIfStale && !_cacheFresh(p.id)) {
        unawaited(
          _fetchChatModels(p.id, notifyError: false, silent: true),
        );
      }
      return List.unmodifiable(cached);
    }
    return _fetchChatModels(p.id, notifyError: true);
  }

  /// 静默强制刷新（不亮加载态）；供下拉打开后 TTL 过期合并用。
  Future<List<ProviderModelInfo>> refreshChatModelsSilent() async {
    final p = _providers.activeProvider;
    if (p == null || !p.canChat) {
      return const [];
    }
    return _fetchChatModels(p.id, notifyError: false, silent: true);
  }

  Future<List<ProviderModelInfo>> _fetchChatModels(
    String providerId, {
    required bool notifyError,
    bool silent = false,
  }) async {
    if (!silent) {
      _modelsLoading = true;
      if (notifyError) _modelsError = null;
      notifyListeners();
    }
    var shouldNotify = !silent;
    try {
      final list = await _providers.listModels(providerId);
      final prev = _modelsCache[providerId];
      final unchanged = _sameModelIds(prev, list);
      _modelsCache[providerId] = list;
      _modelsCacheAt[providerId] = DateTime.now();
      _modelsError = null;
      // 静默刷新且列表未变：只更新时间戳，不通知，避免 Flyout 闪烁
      if (silent) {
        shouldNotify = !unchanged;
      }
      return List.unmodifiable(list);
    } catch (e) {
      if (notifyError || _modelsCache[providerId] == null) {
        _modelsError = e.toString();
        shouldNotify = true;
      } else if (silent) {
        shouldNotify = false;
      }
      return List.unmodifiable(_modelsCache[providerId] ?? const []);
    } finally {
      if (!silent) {
        _modelsLoading = false;
      }
      if (shouldNotify) {
        notifyListeners();
      }
    }
  }

  bool get isStreamingActiveSession =>
      generation.isCurrent(_sessions.activeId);

  bool get canSend {
    if (generation.isCurrent(_sessions.activeId)) return false;
    return _providers.hasConfiguredChatProvider;
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

  void stop() {
    final sid = generation.sessionId;
    if (sid == null) return;
    generation.abort(sid);
  }

  Future<void> send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return;

    final creds = _providers.activeChatCredentials;
    if (creds == null) {
      _setBanner('请先配置提供商与 API Key');
      return;
    }

    var session = _sessions.activeSession;
    session ??= await _sessions.createSession();
    final sessionId = session.id;

    if (generation.isCurrent(sessionId)) return;

    clearBannerError();

    final historyBefore = List<ChatMessage>.from(session.messages);

    final userMsg = await _sessions.appendMessage(
      sessionId,
      role: ChatRole.user,
      content: text,
    );
    if (userMsg == null) return;

    final chatModel = creds.chatModel;
    final assistantMsg = await _sessions.appendMessage(
      sessionId,
      role: ChatRole.assistant,
      content: '',
      streaming: true,
      model: chatModel,
    );
    if (assistantMsg == null) return;
    _streamingAssistantId = assistantMsg.id;

    final defaults = _chatDefaults.defaults;
    final historyForApi = [...historyBefore, userMsg];
    final trimmed = trimChatMessages(
      historyForApi,
      enabled: defaults.contextTrimEnabled,
      maxTurns: defaults.contextMaxTurns,
      maxCharsEnabled: defaults.contextMaxCharsEnabled,
      maxChars: defaults.contextMaxChars,
    );
    final systemPrompt =
        session.overrides.systemPrompt ?? defaults.systemPrompt;
    final apiMessages = buildApiMessages(
      history: trimmed.messages,
      systemPrompt: systemPrompt,
    );
    final temperature =
        session.overrides.temperature ?? defaults.temperature;
    final maxTokens = defaults.maxTokens > 0 ? defaults.maxTokens : null;

    final streamClient = http.Client();
    final token = generation.begin(sessionId, streamClient.close);
    notifyListeners();

    final sw = Stopwatch()..start();
    try {
      await _chatClient.streamChatWithCredentials(
        creds,
        messages: apiMessages,
        temperature: temperature,
        maxTokens: maxTokens,
        timeout: defaults.apiTimeout,
        client: streamClient,
        onDelta: (delta, full) {
          unawaited(_onDelta(sessionId, assistantMsg.id, delta, full));
        },
      );
      await _sessions.updateMessage(
        sessionId,
        assistantMsg.id,
        streaming: false,
        stopped: false,
        error: false,
        clearErrorMessage: true,
        model: chatModel,
        latencyMs: sw.elapsedMilliseconds,
        persist: true,
      );
    } on ChatAbortException {
      await _sessions.updateMessage(
        sessionId,
        assistantMsg.id,
        streaming: false,
        stopped: true,
        model: chatModel,
        latencyMs: sw.elapsedMilliseconds,
        persist: true,
      );
    } catch (e) {
      if (isAbortLike(e)) {
        await _sessions.updateMessage(
          sessionId,
          assistantMsg.id,
          streaming: false,
          stopped: true,
          model: chatModel,
          latencyMs: sw.elapsedMilliseconds,
          persist: true,
        );
      } else {
        final msg = toChatErrorMessage(e, '请求失败');
        await _sessions.updateMessage(
          sessionId,
          assistantMsg.id,
          streaming: false,
          error: true,
          errorMessage: msg,
          model: chatModel,
          latencyMs: sw.elapsedMilliseconds,
          persist: true,
        );
        final logs = _appLogs;
        if (logs != null) {
          unawaited(
            logs.append(
              level: AppLogLevel.error,
              source: AppLogSources.chat,
              message: msg,
            ),
          );
        }
      }
    } finally {
      _streamingAssistantId = null;
      generation.end(sessionId, token);
      try {
        streamClient.close();
      } catch (_) {}
      await _sessions.updateMessage(
        sessionId,
        assistantMsg.id,
        model: chatModel,
        latencyMs: sw.elapsedMilliseconds,
        persist: true,
      );
      notifyListeners();
    }
  }

  Future<void> _onDelta(
    String sessionId,
    String messageId,
    String delta,
    String full,
  ) async {
    if (_streamingAssistantId != messageId) return;
    final now = DateTime.now();
    final shouldPersist = _lastPersistAt == null ||
        now.difference(_lastPersistAt!) > const Duration(milliseconds: 400);
    if (shouldPersist) _lastPersistAt = now;
    await _sessions.updateMessage(
      sessionId,
      messageId,
      content: full,
      streaming: true,
      persist: shouldPersist,
    );
  }

  @override
  void dispose() {
    if (_ownsClient) _chatClient.close();
    super.dispose();
  }
}
