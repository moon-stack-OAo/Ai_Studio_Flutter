import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../image/image_asset_store.dart';
import '../image/image_models.dart';
import '../logging/app_log_entry.dart';
import '../logging/app_log_level.dart';
import '../logging/app_log_repository.dart';
import '../openai/chat_client.dart';
import '../provider/provider_connection.dart';
import '../provider/provider_models_cache.dart';
import '../provider/provider_repository.dart';
import '../security/safe_http_client.dart';
import '../settings/chat_defaults_repository.dart';
import '../util/id.dart';
import 'chat_attach.dart';
import 'chat_context_trim.dart';
import 'chat_errors.dart';
import 'chat_models.dart';
import 'chat_session_repository.dart';
import 'generation_gates.dart';
import 'generation_runtime.dart';

/// 对话发送 / 停止编排（无 UI 绑定，DESIGN.md §5.1 / CHAT-ATTACH）。
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

  /// 发送门闩（提供商已配置且未占用）；正文/附图由 UI 或 [canSendWith] 再判。
  bool get canSend => canSendChatMessage(
        generation: generation,
        activeSessionId: _sessions.activeId,
        hasConfiguredChatProvider: _providers.hasConfiguredChatProvider,
      );

  /// 含正文 / 附图的发送门闩（CHAT-ATTACH：有图可空文）。
  bool canSendWith({
    String textDraft = '',
    bool hasAttachments = false,
  }) {
    return canSendChatMessage(
      generation: generation,
      activeSessionId: _sessions.activeId,
      hasConfiguredChatProvider: _providers.hasConfiguredChatProvider,
      textDraft: textDraft,
      hasAttachments: hasAttachments,
    );
  }

  /// 当前活跃对话模型是否支持视觉（启发式）。
  bool get activeChatSupportsVision {
    final model = _providers.activeChatCredentials?.chatModel;
    return supportsChatVision(model);
  }

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
  /// [attachmentBytes] 非空时允许 [raw] 为空；会落盘为 CHAT-ATTACH 资产。
  /// [onNotify] 在 begin/finally 等需刷新 UI 时调用。
  /// [onBanner] 配置缺失或（可选）流式错误时的横幅。
  /// [bannerOnStreamError] 为 true 时，非取消类错误也会回调 [onBanner]。
  Future<void> send(
    String raw, {
    required VoidCallback onNotify,
    void Function(String? message)? onBanner,
    bool bannerOnStreamError = false,
    List<Uint8List>? attachmentBytes,
    List<String?>? attachmentMimes,
  }) async {
    final text = raw.trim();
    final bytesList = attachmentBytes ?? const <Uint8List>[];
    final hasAtt = bytesList.isNotEmpty;

    if (text.isEmpty && !hasAtt) return;

    final creds = _providers.activeChatCredentials;
    if (creds == null) {
      onBanner?.call('请先配置提供商与 API Key');
      return;
    }

    if (hasAtt) {
      if (!supportsChatVision(creds.chatModel)) {
        onBanner?.call('当前模型不支持图片，请更换支持视觉的对话模型');
        return;
      }
      if (bytesList.length > maxChatAttachments) {
        onBanner?.call('每条消息最多附加 $maxChatAttachments 张图片');
        return;
      }
      for (var i = 0; i < bytesList.length; i++) {
        final mime =
            attachmentMimes != null && i < attachmentMimes.length
                ? attachmentMimes[i]
                : null;
        final err = validateChatAttachmentBytes(bytesList[i], mime: mime);
        if (err != null) {
          onBanner?.call(err);
          return;
        }
      }
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

    final msgId = createId('msg');
    List<ImageRef> attachments = const [];
    if (hasAtt) {
      attachments = await _sessions.persistAttachments(
        msgId,
        bytesList,
        mimes: attachmentMimes,
      );
      if (attachments.isEmpty) {
        onBanner?.call('图片未能保存，请重试');
        return;
      }
    }

    final userMsg = await _sessions.appendMessage(
      sessionId,
      id: msgId,
      role: ChatRole.user,
      content: text,
      attachments: attachments,
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

    final attachmentDataUrls =
        await _collectAttachmentDataUrls(trimmed.messages);
    final apiMessages = buildApiMessages(
      history: trimmed.messages,
      systemPrompt: systemPrompt,
      attachmentDataUrls: attachmentDataUrls,
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

  Future<Map<String, List<String>>> _collectAttachmentDataUrls(
    List<ChatMessage> messages,
  ) async {
    final out = <String, List<String>>{};
    for (final m in messages) {
      if (m.role != ChatRole.user || m.attachments.isEmpty) continue;
      final urls = <String>[];
      for (final ref in m.attachments) {
        final url = await _attachmentToDataUrl(ref);
        if (url != null && url.isNotEmpty) urls.add(url);
      }
      if (urls.isNotEmpty) out[m.id] = urls;
    }
    return out;
  }

  Future<String?> _attachmentToDataUrl(ImageRef ref) async {
    switch (ref.type) {
      case ImageRefType.url:
        final s = ref.src.trim();
        return s.isEmpty ? null : s;
      case ImageRefType.b64:
        return toDataUrlPng(ref.src);
      case ImageRefType.file:
        final bytes = await _sessions.readAttachmentBytes(ref);
        if (bytes == null || bytes.isEmpty) return null;
        final mime = sniffImageMime(bytes) ?? 'image/png';
        return 'data:$mime;base64,${base64Encode(bytes)}';
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
