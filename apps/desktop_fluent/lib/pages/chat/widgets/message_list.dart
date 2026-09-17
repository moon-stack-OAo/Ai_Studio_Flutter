import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../../widgets/empty_illustrations.dart';
import '../../../widgets/fluent_empty_states.dart';
import 'message_bubble.dart';
import 'tool_call_trace_card.dart';

class MessageList extends StatefulWidget {
  const MessageList({
    super.key,
    required this.messages,
    this.onRecallUser,
    this.recallEnabled = false,
    this.emptyHint,
    this.emptySubtitle,
    this.emptyActionLabel,
    this.onEmptyAction,
    this.liveToolTraces = const [],
  });

  final List<ChatMessage> messages;
  final ValueChanged<String>? onRecallUser;
  final bool recallEnabled;
  final String? emptyHint;
  final String? emptySubtitle;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;
  final List<ChatToolCallTrace> liveToolTraces;

  @override
  State<MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<MessageList> {
  final ScrollController _scroll = ScrollController();
  int _lastCount = 0;
  String _lastTail = '';

  @override
  void didUpdateWidget(covariant MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final count = widget.messages.length;
    final tail = count == 0 ? '' : widget.messages.last.content;
    final liveSig = widget.liveToolTraces
        .map((t) => '${t.toolCallId}:${t.status.wire}')
        .join('|');
    final nextTail = '$tail#$liveSig';
    if (count != _lastCount || nextTail != _lastTail) {
      _lastCount = count;
      _lastTail = nextTail;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: FluentMotion.micro,
      curve: FluentMotion.standard,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.messages.isEmpty && widget.liveToolTraces.isEmpty) {
      return FluentContentEmpty(
        hint: widget.emptyHint ?? '开始第一条对话',
        subtitle: widget.emptySubtitle,
        illustration: const FluentEmptyIllustration.noMessages(),
        actionLabel: widget.emptyActionLabel,
        onAction: widget.onEmptyAction,
      );
    }

    String? lastUserId;
    for (var i = widget.messages.length - 1; i >= 0; i--) {
      if (widget.messages[i].role == ChatRole.user) {
        lastUserId = widget.messages[i].id;
        break;
      }
    }

    final items = groupChatMessagesForDisplay(widget.messages);
    final live = widget.liveToolTraces;
    final extra = live.isEmpty ? 0 : 1;
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 12),
      itemCount: items.length + extra,
      itemBuilder: (context, index) {
        if (index >= items.length) {
          return Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 780),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ToolCallTraceGroup(traces: live),
              ),
            ),
          );
        }
        final item = items[index];
        if (item is ChatDisplayToolRound) {
          return Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 780),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ToolCallTraceGroup(traces: item.traces),
              ),
            ),
          );
        }
        final msgItem = item as ChatDisplayMessage;
        final msg = msgItem.message;
        final canRecall = widget.recallEnabled &&
            msg.role == ChatRole.user &&
            msg.id == lastUserId;
        final isUser = msg.role == ChatRole.user;
        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: MessageBubble(
              message: msg,
              recallEnabled: canRecall,
              hideToolCallsStrip: msgItem.hideToolCallsStrip,
              onRecall: canRecall && widget.onRecallUser != null
                  ? () => widget.onRecallUser!(msg.id)
                  : null,
            ),
          ),
        );
      },
    );
  }
}
