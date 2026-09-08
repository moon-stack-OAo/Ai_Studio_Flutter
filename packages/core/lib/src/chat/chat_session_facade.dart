import 'dart:async';

import 'package:flutter/foundation.dart';

import '../logging/app_log_entry.dart';
import '../logging/app_log_level.dart';
import '../logging/app_log_repository.dart';
import '../openai/chat_client.dart';
import '../provider/provider_connection.dart';
import '../provider/provider_models_cache.dart';
import '../provider/provider_repository.dart';
import '../security/safe_http_client.dart';
import '../settings/chat_defaults_repository.dart';
import 'chat_context_trim.dart';
import 'chat_errors.dart';
import 'chat_models.dart';
import 'chat_session_repository.dart';
import 'generation_gates.dart';
import 'generation_runtime.dart';

/// 对话发送 / 停止编排（无 UI 绑定，DESIGN.md §5.1）。
///
/// 持有模型 TTL 缓存与流式发送状态机；app 层 [ChangeNotifier] 仅做薄包装。
class ChatSessionFacade {
  ChatSessionFacade({
    required ProviderRepository providers,
    required ChatSessionRepository sessions,
    required ChatDefaultsRepository chatDefaults,
    required this.generation,
    AppLogRepository? appLogs,
    OpenAiCompatibleChatClient? chatClient,
    VoidCallback? onModelsChanged,
  })  : _providers = providers,
        _sessions = sessions,
        _chatDefaults = chatDefaults,
        _appLogs = appLogs,
        _ownsClient = chatClient == null,
        _chatClient = chatClient ?? OpenAiCompatibleChatClient(),
        modelsCache = ProviderModelsCache(
          providers: providers,
          onChanged: onModelsChanged,
        );

  final ProviderRepository _providers;
  final ChatSessionRepository _sessions;
  final ChatDefaultsRepository _chatDefaults;
  final AppLogRepository? _appLogs;
  final GenerationRuntime generation;
  final OpenAiCompatibleChatClient _chatClient;
  final bool _ownsClient;

  final ProviderModelsCache modelsCache;

  String? _streamingAssistantId;
  DateTime? _lastPersistAt;

  bool get isStreamingActiveSession =>
      generation.isCurrent(_sessions.activeId);

  bool get canSend => canSendChatMessage(
        generation: generation,
        activeSessionId: _sessions.activeId,
        hasConfiguredChatProvider: _providers.hasConfiguredChatProvider,
      );

  /// 拉取对话模型列表（仅 [ProviderConfig.canChat]）。
  Future<List<ProviderModelInfo>> loadChatModels({
    bool force = false,
    bool silentRefreshIfStale = true,
  }) {
    return modelsCache.load(
      force: force,
      silentRefreshIfStale: silentRefreshIfStale,
      canUse: (p) => p.canChat,
    );
  }

  void stop() {
    final sid = generation.sessionId;
    if (sid == null) return;
    generation.abort(sid);
  }

  /// 发送一条用户消息并流式写入助手气泡。
  ///
  /// [onNotify] 在 begin/finally 等需刷新 UI 时调用。
  /// [onBanner] 配置缺失或（可选）流式错误时的横幅。
  /// [bannerOnStreamError] 为 true 时，非取消类错误也会回调 [onBanner]。
  Future<void> send(
    String raw, {
    required VoidCallback onNotify,
    void Function(String? message)? onBanner,
    bool bannerOnStreamError = false,
  }) async {
    final text = raw.trim();
    if (text.isEmpty) return;

    final creds = _providers.activeChatCredentials;
    if (creds == null) {
      onBanner?.call('请先配置提供商与 API Key');
      return;
    }

    var session = _sessions.activeSession;
    session ??= await _sessions.createSession();
    final sessionId = session.id;

    if (isGenerationBlocked(
      generation: generation,
      activeSessionId: sessionId,
    )) {
      return;
    }

    onBanner?.call(null);

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

    final streamClient = createSafeHttpClient();
    final token = generation.begin(sessionId, streamClient.close);
    onNotify();

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
        if (bannerOnStreamError) {
          onBanner?.call(msg);
        }
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
      onNotify();
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

  void dispose() {
    modelsCache.dispose();
    if (_ownsClient) _chatClient.close();
  }
}
