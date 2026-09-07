import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';

import '../../widgets/material_empty_states.dart';
import 'chat_controller.dart';
import 'session_list_page.dart';
import 'widgets/chat_model_picker_sheet.dart';
import 'widgets/composer.dart';
import 'widgets/message_list.dart';
import 'widgets/session_overrides_sheet.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.providerRepository,
    required this.sessionRepository,
    required this.chatDefaultsRepository,
    required this.generation,
    this.appLogRepository,
    this.chatClient,
    this.onOpenProviders,
  });

  final ProviderRepository providerRepository;
  final ChatSessionRepository sessionRepository;
  final ChatDefaultsRepository chatDefaultsRepository;
  final GenerationRuntime generation;
  final AppLogRepository? appLogRepository;
  final OpenAiCompatibleChatClient? chatClient;
  final VoidCallback? onOpenProviders;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final ChatController _controller;
  String? _lastBanner;

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
    );
    _controller.addListener(_onControllerChanged);
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
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openSessions() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
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
        widget.sessionRepository,
        widget.generation,
        _controller,
      ]),
      builder: (context, _) {
        final ready = widget.providerRepository.hasConfiguredChatProvider;
        if (!ready) {
          return MaterialFeatureEmpty(
            appBarTitle: '对话',
            title: '开始对话',
            message: '尚未配置提供商。前往设置添加 API Key，即可开始流式对话。',
            actionLabel: '添加提供商',
            onAction: widget.onOpenProviders,
          );
        }

        final session = widget.sessionRepository.activeSession;
        final messages = session?.messages ?? const <ChatMessage>[];
        final creds = widget.providerRepository.activeChatCredentials;
        final modelLabel = creds?.chatModel ?? '';
        final streamingHere = _controller.isStreamingActiveSession;
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
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: _openModelPicker,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 148),
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
              if (session != null)
                IconButton(
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
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: MessageList(
                  messages: messages,
                  recallEnabled: !streamingHere,
                  onRecallUser: (id) => _controller.recallUserMessage(id),
                  emptyHint: '输入消息开始对话',
                  emptySubtitle: '在下方输入第一条消息，或打开会话列表新建。',
                ),
              ),
              Composer(
                enabled: _controller.canSend,
                streaming: streamingHere,
                onSend: _controller.send,
                onStop: _controller.stop,
              ),
            ],
          ),
        );
      },
    );
  }
}
