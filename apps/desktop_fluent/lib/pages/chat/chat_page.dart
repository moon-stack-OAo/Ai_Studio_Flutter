import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../widgets/empty_illustrations.dart';
import '../../widgets/fluent_empty_states.dart';
import '../../widgets/session_list_pane.dart';
import 'chat_controller.dart';
import 'widgets/chat_model_combo.dart';
import 'widgets/composer.dart';
import 'widgets/message_list.dart';
import 'widgets/session_overrides_dialog.dart';
import 'widgets/tool_auth_dialog.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.providerRepository,
    required this.sessionRepository,
    required this.chatDefaultsRepository,
    required this.generation,
    this.appLogRepository,
    this.chatClient,
    this.mcpServerRepository,
    this.mcpSessionFactory,
    this.onOpenProviders,
    this.onOpenMcp,
  });

  final ProviderRepository providerRepository;
  final ChatSessionRepository sessionRepository;
  final ChatDefaultsRepository chatDefaultsRepository;
  final GenerationRuntime generation;
  final AppLogRepository? appLogRepository;
  final OpenAiCompatibleChatClient? chatClient;
  final McpServerRepository? mcpServerRepository;
  final McpSessionFactory? mcpSessionFactory;
  final VoidCallback? onOpenProviders;
  final VoidCallback? onOpenMcp;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final ChatController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ChatController(
      providerRepository: widget.providerRepository,
      sessionRepository: widget.sessionRepository,
      chatDefaultsRepository: widget.chatDefaultsRepository,
      appLogRepository: widget.appLogRepository,
      generation: widget.generation,
      chatClient: widget.chatClient,
      mcpServerRepository: widget.mcpServerRepository,
      mcpSessionFactory: widget.mcpSessionFactory,
      toolAuthPrompter: _promptToolAuth,
    );
  }

  Future<bool> _promptToolAuth(ToolAuthPrompt prompt) {
    if (!mounted) return Future.value(false);
    return showToolAuthDialog(context: context, prompt: prompt);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _flashBannerIfNeeded() {
    final pending = _controller.bannerError;
    if (pending == null || pending.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final banner = _controller.bannerError;
      if (banner == null || banner.isEmpty) return;
      _controller.clearBannerError();
      displayInfoBar(
        context,
        builder: (ctx, close) => InfoBar(
          title: Text(banner),
          severity: InfoBarSeverity.error,
          onClose: close,
        ),
      );
    });
  }

  Future<void> _openOverrides(ChatSession session) async {
    await showSessionOverridesDialog(
      context: context,
      session: session,
      defaults: widget.chatDefaultsRepository.defaults,
      onSave: _controller.setSessionOverrides,
    );
  }

  String _sessionSubtitle(ChatSession s) {
    final busy = widget.generation.sessionId == s.id;
    final time = _relativeDay(s.updatedAt);
    if (busy) return '$time · 流式输出中';
    if (s.messages.isEmpty) return '$time · 空闲';
    return time;
  }

  String _relativeDay(int ms) {
    if (ms <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    if (day == today) return '今天';
    if (day == today.subtract(const Duration(days: 1))) return '昨天';
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final diff = today.difference(day).inDays;
    if (diff > 0 && diff < 7) return weekdays[dt.weekday - 1];
    return '${dt.month}/${dt.day}';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.providerRepository,
        widget.sessionRepository,
        widget.generation,
        _controller,
        ?widget.mcpServerRepository,
      ]),
      builder: (context, _) {
        final ready = widget.providerRepository.hasConfiguredChatProvider;
        if (!ready) {
          return FluentFeatureEmpty(
            title: '尚未配置提供商',
            message: '前往设置添加 API Key 后，即可开始流式对话。',
            actionLabel: '去设置',
            onAction: widget.onOpenProviders,
            illustration: const FluentEmptyIllustration.noProvider(),
          );
        }

        final session = widget.sessionRepository.activeSession;
        final messages = session?.messages ?? const <ChatMessage>[];
        final streamingHere = _controller.isStreamingActiveSession;
        final hasOverrides = session != null && !session.overrides.isEmpty;
        _flashBannerIfNeeded();

        return ColoredBox(
          color: tokens.canvas,
          child: FocusTraversalGroup(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: tokens.settingsCatWidth,
                  child: SessionListPane(
                    sessions: [
                      for (final s in widget.sessionRepository.sortedSessions)
                        SessionListItem(
                          id: s.id,
                          title: s.title,
                          subtitle: _sessionSubtitle(s),
                        ),
                    ],
                    selectedId: widget.sessionRepository.activeId,
                    busySessionId: widget.generation.sessionId,
                    onSelect: (id) => _controller.setActiveSession(id),
                    onCreate: () => _controller.createSession(),
                    onDelete: (id) => _controller.removeSession(id),
                    onRename: (id, title) =>
                        _controller.renameSession(id, title),
                  ),
                ),
                Container(width: 1, color: tokens.border),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ChatHeader(
                        title: session?.title ?? '新对话',
                        tokens: tokens,
                        controller: _controller,
                        hasOverrides: hasOverrides,
                        onOpenOverrides: session == null
                            ? null
                            : () => _openOverrides(session),
                      ),
                      Expanded(
                        child: MessageList(
                          messages: messages,
                          recallEnabled: !streamingHere,
                          onRecallUser: (id) =>
                              _controller.recallUserMessage(id),
                          emptyHint: '开始第一条对话',
                          emptySubtitle: '当前会话还没有消息，在下方输入即可开始。',
                          liveToolTraces: _controller.liveToolTraces,
                        ),
                      ),
                      if (_controller.mcpStatusHint != null)
                        _McpStatusBanner(
                          message: _controller.mcpStatusHint!,
                          tokens: tokens,
                          onOpenMcp: widget.onOpenMcp,
                          onDismiss: _controller.mcpStatusHintDismissible
                              ? () {
                                  // ignore: discarded_futures
                                  _controller.dismissMcpStatusHint();
                                }
                              : null,
                        ),
                      Composer(
                        enabled: _controller.canSend,
                        streaming: streamingHere,
                        onSend: _controller.send,
                        onStop: _controller.stop,
                        visionSupported: _controller.activeChatSupportsVision,
                        draftAttachments: _controller.draftAttachments,
                        onPickAttachments: streamingHere
                            ? null
                            : () => _controller.pickAttachments(),
                        onDropAttachment: streamingHere
                            ? null
                            : _controller.dropAttachment,
                        onRemoveDraftAttachment:
                            _controller.removeDraftAttachmentAt,
                        canSendWithDraft: (text) =>
                            _controller.canSendWith(textDraft: text),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _McpStatusBanner extends StatelessWidget {
  const _McpStatusBanner({
    required this.message,
    required this.tokens,
    this.onOpenMcp,
    this.onDismiss,
  });

  final String message;
  final FluentTokens tokens;
  final VoidCallback? onOpenMcp;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        color: Color.lerp(tokens.warning, tokens.surface, 0.9),
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12,
                color: tokens.inkSecondary,
                fontFamily: tokens.fontFamily,
              ),
            ),
          ),
          if (onOpenMcp != null)
            HyperlinkButton(
              onPressed: onOpenMcp,
              child: const Text('打开 MCP 设置'),
            ),
          if (onDismiss != null)
            Tooltip(
              message: '不再提示',
              child: IconButton(
                icon: const Icon(FluentIcons.chrome_close, size: 12),
                onPressed: onDismiss,
              ),
            ),
        ],
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.title,
    required this.tokens,
    required this.controller,
    required this.hasOverrides,
    this.onOpenOverrides,
  });

  final String title;
  final FluentTokens tokens;
  final ChatController controller;
  final bool hasOverrides;
  final VoidCallback? onOpenOverrides;

  @override
  Widget build(BuildContext context) {
    return Container(
      // 不锁死 48：字号/系统缩放极端档下模型 chip 与「会话参数」需可撑高。
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Color.lerp(tokens.surface, tokens.canvas, 0.15),
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      // OD commandbar：标题 + 模型 Combo + spacer + 行尾「会话参数」
      child: Row(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: tokens.ink,
                fontFamily: tokens.fontFamily,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ChatModelCombo(controller: controller),
          const Spacer(),
          if (onOpenOverrides != null)
            Semantics(
              button: true,
              label: hasOverrides ? '会话参数，已覆盖默认值' : '会话参数',
              excludeSemantics: true,
              child: Tooltip(
                message: hasOverrides ? '会话参数（已覆盖）' : '会话参数',
                child: HoverButton(
                  onPressed: onOpenOverrides,
                  cursor: SystemMouseCursors.click,
                  builder: (context, states) {
                    final hovered = states.isHovered || states.isPressed;
                    final focused = states.isFocused;
                    return Container(
                      constraints: const BoxConstraints(minHeight: 30),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: hovered || focused
                            ? tokens.surfaceMuted
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: focused
                              ? tokens.primary.withValues(alpha: 0.55)
                              : (hovered
                                  ? tokens.border
                                  : Colors.transparent),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '会话参数',
                            style: TextStyle(
                              fontSize: 12,
                              color: tokens.inkSecondary,
                              fontFamily: tokens.fontFamily,
                            ),
                          ),
                          if (hasOverrides) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: tokens.primary.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color:
                                      tokens.primary.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Text(
                                '已覆盖',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: tokens.primaryPressed,
                                  fontFamily: tokens.fontFamily,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
