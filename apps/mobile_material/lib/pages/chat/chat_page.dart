import 'dart:async';

import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';

import '../../widgets/empty_illustrations.dart';
import '../../widgets/material_empty_states.dart';
import '../../widgets/skill_summary.dart';
import 'chat_controller.dart';
import 'session_list_page.dart';
import 'widgets/chat_model_picker_sheet.dart';
import 'widgets/composer.dart';
import 'widgets/message_list.dart';
import 'widgets/session_overrides_sheet.dart';
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
    this.skillRepository,
  });

  final ProviderRepository providerRepository;
  final SkillRepository? skillRepository;
  final ChatSessionRepository sessionRepository;
  final ChatDefaultsRepository chatDefaultsRepository;
  final GenerationRuntime generation;
  final AppLogRepository? appLogRepository;
  final OpenAiCompatibleChatClient? chatClient;
  final McpServerRepository? mcpServerRepository;
  final McpSessionFactory? mcpSessionFactory;
  final VoidCallback? onOpenProviders;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final ChatController _controller;
  late final SkillRepository _skills;
  late final ValueNotifier<(String?, String?, ChatOverrides?)> _sessionChrome;
  String? _lastBanner;

  (String?, String?, ChatOverrides?) _chromeSignature() {
    final session = widget.sessionRepository.activeSession;
    return (session?.id, session?.title, session?.overrides);
  }

  void _onSessionChanged() {
    _sessionChrome.value = _chromeSignature();
  }

  @override
  void initState() {
    super.initState();
    _sessionChrome = ValueNotifier(_chromeSignature());
    widget.sessionRepository.addListener(_onSessionChanged);
    _skills =
        widget.skillRepository ?? SkillRepository(storage: MemorySkillStorage());
    if (!_skills.isLoaded) unawaited(_skills.load().catchError((Object _) {}));
    _controller = ChatController(
      skillRepository: _skills,
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
    _controller.addListener(_onControllerChanged);
  }

  Future<bool> _promptToolAuth(ToolAuthPrompt prompt) {
    if (!mounted) return Future.value(false);
    return showToolAuthDialog(context: context, prompt: prompt);
  }

  void _onControllerChanged() {
    final banner = _controller.bannerError;
    if (banner != null &&
        banner.isNotEmpty &&
        banner != _lastBanner &&
        mounted) {
      _lastBanner = banner;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(banner),
          action: SnackBarAction(
            label: '关闭',
            onPressed: _controller.clearBannerError,
          ),
        ),
      );
    }
    if (banner == null) _lastBanner = null;
  }

  @override
  void dispose() {
    widget.sessionRepository.removeListener(_onSessionChanged);
    _sessionChrome.dispose();
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    if (widget.skillRepository == null) _skills.dispose();
    super.dispose();
  }

  Future<void> _openSessions() async {
    await Navigator.of(context).push<void>(
      materialFadeSlideRoute(
        builder: (context) {
          return ListenableBuilder(
            listenable: Listenable.merge([
              widget.sessionRepository,
              widget.generation,
            ]),
            builder: (context, _) {
              return SessionListPage(
                sessions: widget.sessionRepository.sortedSessions,
                activeId: widget.sessionRepository.activeId,
                streamingSessionId: widget.generation.sessionId,
                onSelect: (id) => _controller.setActiveSession(id),
                onCreate: () => _controller.createSession(),
                onDelete: (id) => _controller.removeSession(id),
                onRename: (id, title) => _controller.renameSession(id, title),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openModelPicker() async {
    await showChatModelPickerSheet(
      context: context,
      controller: _controller,
    );
  }

  Future<void> _openOverrides(ChatSession session) async {
    await showSessionOverridesSheet(
      context: context,
      session: session,
      defaults: widget.chatDefaultsRepository.defaults,
      onSave: _controller.setSessionOverrides,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.providerRepository,
        _sessionChrome,
      ]),
      builder: (context, _) {
        final ready = widget.providerRepository.hasConfiguredChatProvider;
        if (!ready) {
          return MaterialFeatureEmpty(
            appBarTitle: '对话',
            title: '尚未配置提供商',
            message: '前往设置添加 API Key 后，即可开始流式对话。',
            actionLabel: '去设置',
            onAction: widget.onOpenProviders,
            illustration: const MaterialEmptyIllustration.noProvider(),
          );
        }

        final session = widget.sessionRepository.activeSession;
        final creds = widget.providerRepository.activeChatCredentials;
        final modelLabel = creds?.chatModel ?? '';
        final title = session?.title ?? '新对话';
        final hasOverrides = session != null && !session.overrides.isEmpty;

        return Scaffold(
          backgroundColor: tokens.canvas,
          resizeToAvoidBottomInset: true,
          appBar: AppBar(
            title: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            leading: IconButton(
              tooltip: '会话列表',
              icon: const Icon(Icons.menu),
              onPressed: _openSessions,
            ),
            actions: [
              if (creds != null)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Center(
                    child: Semantics(
                      button: true,
                      label: modelLabel.isEmpty
                          ? '选择模型'
                          : '当前模型 $modelLabel，点按更换',
                      excludeSemantics: true,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: _openModelPicker,
                        child: Container(
                          constraints: const BoxConstraints(
                            maxWidth: 148,
                            minHeight: 36,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.surfaceMuted,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: tokens.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  modelLabel.isEmpty ? '选择模型' : modelLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: tokens.inkSecondary,
                                    fontFamily: tokens.fontFamily,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 2),
                              Icon(
                                Icons.expand_more,
                                size: 16,
                                color: tokens.inkMuted,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (session != null)
                Semantics(
                  button: true,
                  label: hasOverrides ? '会话参数，已覆盖默认值' : '会话参数',
                  excludeSemantics: true,
                  child: IconButton(
                    tooltip: hasOverrides ? '会话参数（已覆盖）' : '会话参数',
                    onPressed: () => _openOverrides(session),
                    icon: Badge(
                      isLabelVisible: hasOverrides,
                      smallSize: 8,
                      child: Icon(
                        Icons.tune,
                        color: hasOverrides ? tokens.primary : null,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListenableBuilder(
                  listenable: Listenable.merge([
                    widget.sessionRepository,
                    widget.generation,
                    _controller,
                  ]),
                  builder: (context, _) {
                    final active = widget.sessionRepository.activeSession;
                    return MessageList(
                      key: ValueKey(active?.id),
                      messages: active?.messages ?? const <ChatMessage>[],
                      recallEnabled: !_controller.isStreamingActiveSession,
                      onRecallUser: (id) => _controller.recallUserMessage(id),
                      emptyHint: '开始第一条对话',
                      emptySubtitle: '当前会话还没有消息，在下方输入即可开始。',
                      emptySecondaryActionLabel: '打开会话列表',
                      onEmptySecondaryAction: _openSessions,
                      liveToolTraces: _controller.liveToolTraces,
                    );
                  },
                ),
              ),
              ListenableBuilder(
                listenable: Listenable.merge([
                  widget.generation,
                  _controller,
                ]),
                builder: (context, _) {
                  final streamingHere = _controller.isStreamingActiveSession;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: SkillSummary(
                          repository: _skills,
                          target: SkillTarget.chat,
                          enabled: !widget.generation.busy,
                        ),
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
                        onRemoveDraftAttachment:
                            _controller.removeDraftAttachmentAt,
                        canSendWithDraft: (text) =>
                            _controller.canSendWith(textDraft: text),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
