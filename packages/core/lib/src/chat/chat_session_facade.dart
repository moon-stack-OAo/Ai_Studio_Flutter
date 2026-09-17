import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../image/image_asset_store.dart';
import '../image/image_models.dart';
import '../logging/app_log_entry.dart';
import '../logging/app_log_level.dart';
import '../logging/app_log_repository.dart';
import '../mcp/mcp_client.dart';
import '../mcp/mcp_models.dart';
import '../mcp/mcp_openai_tools.dart';
import '../mcp/mcp_sanitize.dart';
import '../mcp/mcp_server_repository.dart';
import '../mcp/mcp_tool_policy.dart';
import '../mcp/tool_call_orchestrator.dart';
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

/// 对话发送 / 停止编排（无 UI 绑定，DESIGN.md §5.1 / CHAT-ATTACH / §5.11）。
///
/// 持有模型 TTL 缓存与流式发送状态机；app 层 [ChangeNotifier] 仅做薄包装。
///
/// **启用 MCP（P6-2）**：构造时注入非空的 [mcpServers]、[mcpSessionFactory]、
/// [toolAuthPrompter]；且活跃模型 [supportsChatTools]、仓库有已启用 Server 的
/// `toolsCache` 时，请求附带 `tools[]`，并在 `hasToolCalls` 时串行编排
/// （policy → 授权 → call → 回灌 → 再 stream）。任一注入为空则走无 MCP 旧路径。
class ChatSessionFacade {
  ChatSessionFacade({
    required ProviderRepository providers,
    required ChatSessionRepository sessions,
    required ChatDefaultsRepository chatDefaults,
    required this.generation,
    AppLogRepository? appLogs,
    OpenAiCompatibleChatClient? chatClient,
    VoidCallback? onModelsChanged,
    McpServerRepository? mcpServers,
    McpSessionFactory? mcpSessionFactory,
    ToolAuthPrompter? toolAuthPrompter,
    ToolCallOrchestrator? toolCallOrchestrator,
    this.maxMcpToolRounds = kDefaultMcpMaxToolRounds,
    ToolCallTraceListener? onToolTrace,
    http.Client Function()? createHttpClient,
  })  : _providers = providers,
        _sessions = sessions,
        _chatDefaults = chatDefaults,
        _appLogs = appLogs,
        _ownsClient = chatClient == null,
        _chatClient = chatClient ?? OpenAiCompatibleChatClient(),
        _mcpServers = mcpServers,
        _mcpSessionFactory = mcpSessionFactory,
        _toolAuthPrompter = toolAuthPrompter,
        _toolCallOrchestrator = toolCallOrchestrator,
        _onToolTrace = onToolTrace,
        _createHttpClient = createHttpClient ?? createSafeHttpClient,
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

  final McpServerRepository? _mcpServers;
  final McpSessionFactory? _mcpSessionFactory;
  final ToolAuthPrompter? _toolAuthPrompter;
  final ToolCallOrchestrator? _toolCallOrchestrator;
  final ToolCallTraceListener? _onToolTrace;
  final http.Client Function() _createHttpClient;
  final int maxMcpToolRounds;

  final Map<String, McpSession> _mcpSessions = {};
  final McpSessionToolGrants _mcpSessionGrants = McpSessionToolGrants();

  final ProviderModelsCache modelsCache;

  String? _streamingAssistantId;
  DateTime? _lastPersistAt;

  bool get isStreamingActiveSession =>
      generation.isCurrent(_sessions.activeId);

  /// 是否具备 MCP 编排注入（不含「当前是否有 tools 缓存」）。
  bool get isMcpWiringEnabled =>
      _mcpServers != null &&
      _mcpSessionFactory != null &&
      _toolAuthPrompter != null;

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

  /// 当前活跃对话模型是否支持 tools（启发式）。
  bool get activeChatSupportsTools {
    final model = _providers.activeChatCredentials?.chatModel;
    return supportsChatTools(model);
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
    var apiMessages = buildApiMessages(
      history: trimmed.messages,
      systemPrompt: systemPrompt,
      attachmentDataUrls: attachmentDataUrls,
    );
    final temperature =
        session.overrides.temperature ?? defaults.temperature;
    final maxTokens = defaults.maxTokens > 0 ? defaults.maxTokens : null;

    final openaiTools = _resolveOpenAiTools(chatModel);
    final mcpActive = openaiTools != null && openaiTools.isNotEmpty;

    final streamClient = _createHttpClient();
    // abort 时关闭 chat client，并关闭进行中的 MCP sessions。
    final token = generation.begin(sessionId, () {
      try {
        streamClient.close();
      } catch (_) {}
      _closeMcpSessions();
    });
    onNotify();

    final sw = Stopwatch()..start();
    var currentAssistantId = assistantMsg.id;
    var aborted = false;
    var errored = false;
    String? errorBanner;

    try {
      var round = 0;
      var totalToolCalls = 0;
      var workingMessages = List<Map<String, dynamic>>.from(apiMessages);

      while (true) {
        if (!_isGenCurrent(sessionId)) {
          aborted = true;
          break;
        }

        final result = await _chatClient.streamChatWithCredentials(
          creds,
          messages: workingMessages,
          temperature: temperature,
          maxTokens: maxTokens,
          tools: openaiTools,
          toolChoice: mcpActive ? 'auto' : null,
          timeout: defaults.apiTimeout,
          client: streamClient,
          onDelta: (delta, full) {
            unawaited(_onDelta(sessionId, currentAssistantId, delta, full));
          },
        );

        if (!_isGenCurrent(sessionId)) {
          aborted = true;
          break;
        }

        if (!mcpActive || !result.hasToolCalls) {
          await _sessions.updateMessage(
            sessionId,
            currentAssistantId,
            content: result.content,
            streaming: false,
            stopped: false,
            error: false,
            clearErrorMessage: true,
            model: chatModel,
            latencyMs: sw.elapsedMilliseconds,
            persist: true,
          );
          break;
        }

        // 有 tool_calls：落盘 assistant（含 toolCalls）→ 编排 → 回灌 → 新助手气泡。
        await _sessions.updateMessage(
          sessionId,
          currentAssistantId,
          content: result.content,
          toolCalls: result.toolCalls,
          streaming: false,
          stopped: false,
          error: false,
          clearErrorMessage: true,
          model: chatModel,
          persist: true,
        );

        round++;
        if (round > maxMcpToolRounds ||
            totalToolCalls >= maxMcpToolRounds) {
          await _sessions.appendMessage(
            sessionId,
            role: ChatRole.assistant,
            content: '已达本回合工具调用上限，已停止继续调用。',
            model: chatModel,
          );
          break;
        }

        final requests = _buildToolRequests(result.toolCalls);
        if (requests.isEmpty) {
          break;
        }

        final remaining = maxMcpToolRounds - totalToolCalls;
        final orchestrator = _resolveOrchestrator();
        final callResults = await orchestrator.runRound(
          calls: requests,
          prompter: _toolAuthPrompter!,
          onTrace: _onToolTrace,
          isCancelled: () => !_isGenCurrent(sessionId),
          options: ToolCallOrchestratorOptions(
            maxRounds: remaining,
            serialCalls: true,
          ),
        );
        totalToolCalls += callResults
            .where((r) => r.status == McpToolCallStatus.success)
            .length;

        if (!_isGenCurrent(sessionId)) {
          aborted = true;
          break;
        }

        // 回灌 role=tool 消息到会话与 API 轨迹。
        workingMessages = [
          ...workingMessages,
          {
            'role': 'assistant',
            'content': result.content,
            'tool_calls':
                result.toolCalls.map((t) => t.toApiJson()).toList(),
          },
        ];

        for (final tr in callResults) {
          final content = tr.content.isEmpty
              ? (tr.isError ? '工具调用失败' : '')
              : tr.content;
          await _sessions.appendMessage(
            sessionId,
            role: ChatRole.tool,
            content: content,
            toolCallId: tr.toolCallId,
          );
          workingMessages.add({
            'role': 'tool',
            'tool_call_id': tr.toolCallId,
            'content': content,
          });
          _logToolResult(tr);
        }

        onNotify();

        // 下一轮助手气泡。
        final next = await _sessions.appendMessage(
          sessionId,
          role: ChatRole.assistant,
          content: '',
          streaming: true,
          model: chatModel,
        );
        if (next == null) break;
        currentAssistantId = next.id;
        _streamingAssistantId = next.id;
      }
    } on ChatAbortException {
      aborted = true;
    } catch (e) {
      if (isAbortLike(e)) {
        aborted = true;
      } else {
        errored = true;
        final msg = toChatErrorMessage(e, '请求失败');
        errorBanner = msg;
        await _sessions.updateMessage(
          sessionId,
          currentAssistantId,
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
      if (aborted && !errored) {
        await _sessions.updateMessage(
          sessionId,
          currentAssistantId,
          streaming: false,
          stopped: true,
          model: chatModel,
          latencyMs: sw.elapsedMilliseconds,
          persist: true,
        );
      }
      _streamingAssistantId = null;
      generation.end(sessionId, token);
      _closeMcpSessions();
      try {
        streamClient.close();
      } catch (_) {}
      await _sessions.updateMessage(
        sessionId,
        currentAssistantId,
        model: chatModel,
        latencyMs: sw.elapsedMilliseconds,
        persist: true,
      );
      if (errorBanner != null && bannerOnStreamError) {
        // already notified
      }
      onNotify();
    }
  }

  List<Map<String, dynamic>>? _resolveOpenAiTools(String chatModel) {
    if (!isMcpWiringEnabled) return null;
    if (!supportsChatTools(chatModel)) return null;
    final repo = _mcpServers!;
    final tools = repo.exposedTools;
    if (tools.isEmpty) return null;
    final mapped = mcpToolsToOpenAiTools(tools);
    return mapped.isEmpty ? null : mapped;
  }

  List<McpToolCallRequest> _buildToolRequests(List<ChatToolCall> calls) {
    final repo = _mcpServers;
    if (repo == null) return const [];
    final enabled = repo.enabledServers;
    final out = <McpToolCallRequest>[];
    for (final c in calls) {
      final name = c.name.trim();
      if (name.isEmpty) continue;
      final server = resolveServerForTool(enabled, name);
      if (server == null) {
        // 无归属：拒绝回灌，不 call。
        out.add(
          McpToolCallRequest(
            toolCallId: c.id,
            serverId: '',
            toolName: name,
            argumentsJson: c.arguments.isEmpty ? '{}' : c.arguments,
            argumentsSummary: mcpArgumentsSummary(c.arguments),
          ),
        );
        continue;
      }
      out.add(
        McpToolCallRequest(
          toolCallId: c.id,
          serverId: server.id,
          toolName: name,
          argumentsJson: c.arguments.isEmpty ? '{}' : c.arguments,
          argumentsSummary: mcpArgumentsSummary(c.arguments),
        ),
      );
    }
    return out;
  }

  ToolCallOrchestrator _resolveOrchestrator() {
    final injected = _toolCallOrchestrator;
    if (injected != null) return injected;
    return DefaultToolCallOrchestrator(
      resolveSession: _sessionFor,
      resolveTool: (serverId, toolName) {
        if (serverId.isEmpty) {
          return McpToolDescriptor(
            name: toolName,
            sideEffect: McpToolSideEffect.unknown,
          );
        }
        final s = _mcpServers!.findById(serverId);
        if (s == null) {
          return McpToolDescriptor(
            name: toolName,
            sideEffect: McpToolSideEffect.unknown,
          );
        }
        return resolveToolDescriptor(s, toolName);
      },
      resolveServer: (serverId) {
        if (serverId.isEmpty) {
          return const McpServerConfig(
            id: '',
            displayName: '未知',
            enabled: false,
          );
        }
        return _mcpServers!.findById(serverId) ??
            McpServerConfig(
              id: serverId,
              displayName: serverId,
              enabled: false,
            );
      },
      sessionGrants: _mcpSessionGrants,
    );
  }

  McpSession _sessionFor(String serverId) {
    final existing = _mcpSessions[serverId];
    if (existing != null) return existing;
    final server = _mcpServers!.findById(serverId);
    if (server == null) {
      throw StateError('MCP Server 不存在: $serverId');
    }
    final session = _mcpSessionFactory!.create(server);
    _mcpSessions[serverId] = session;
    return session;
  }

  void _closeMcpSessions() {
    for (final s in _mcpSessions.values) {
      try {
        s.close();
      } catch (_) {}
    }
    _mcpSessions.clear();
  }

  bool _isGenCurrent(String sessionId) => generation.isCurrent(sessionId);

  void _logToolResult(McpToolCallResult tr) {
    final logs = _appLogs;
    if (logs == null) return;
    final summary = mcpSanitizeSummary(
      '${tr.status.wire} ${tr.toolCallId} ${tr.content}',
      maxLen: 180,
    );
    unawaited(
      logs.append(
        level: tr.isError ? AppLogLevel.warn : AppLogLevel.info,
        source: AppLogSources.chat,
        message: 'MCP tool: $summary',
      ),
    );
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
    _closeMcpSessions();
    if (_ownsClient) _chatClient.close();
  }
}

/// 测试用：对所有 confirm_* 一律允许。
Future<bool> allowAllToolAuthPrompter(ToolAuthPrompt prompt) async => true;

/// 测试用：对所有 confirm_* 一律拒绝。
Future<bool> denyAllToolAuthPrompter(ToolAuthPrompt prompt) async => false;
