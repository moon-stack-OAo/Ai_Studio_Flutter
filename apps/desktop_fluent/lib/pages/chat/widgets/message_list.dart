import 'package:core/core.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../../widgets/empty_illustrations.dart';
import '../../../widgets/fluent_empty_states.dart';
import 'message_bubble.dart';

class MessageList extends StatefulWidget {
  const MessageList({
    super.key,
    required this.messages,
    this.onRecallUser,
    this.recallEnabled = false,
    this.emptyHint,
    this.emptySubtitle,
  });

  final List<ChatMessage> messages;
  final ValueChanged<String>? onRecallUser;
  final bool recallEnabled;
  final String? emptyHint;
  final String? emptySubtitle;

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
    if (count != _lastCount || tail != _lastTail) {
      _lastCount = count;
      _lastTail = tail;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.messages.isEmpty) {
      return FluentContentEmpty(
        hint: widget.emptyHint ?? '还没有消息',
        subtitle: widget.emptySubtitle,
        illustration: const FluentEmptyIllustration.noMessages(),
      );
    }

    String? lastUserId;
    for (var i = widget.messages.length - 1; i >= 0; i--) {
      if (widget.messages[i].role == ChatRole.user) {
        lastUserId = widget.messages[i].id;
        break;
      }
    }

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 12),
      itemCount: widget.messages.length,
      itemBuilder: (context, index) {
        final msg = widget.messages[index];
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
