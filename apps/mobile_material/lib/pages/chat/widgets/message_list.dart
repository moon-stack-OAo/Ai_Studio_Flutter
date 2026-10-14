import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';

import '../../../widgets/empty_illustrations.dart';
import '../../../widgets/material_empty_states.dart';
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
    this.emptySecondaryActionLabel,
    this.onEmptySecondaryAction,
    this.liveToolTraces = const [],
  });

  final List<ChatMessage> messages;
  final ValueChanged<String>? onRecallUser;
  final bool recallEnabled;
  final String? emptyHint;
  final String? emptySubtitle;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;
  final String? emptySecondaryActionLabel;
  final VoidCallback? onEmptySecondaryAction;
  final List<ChatToolCallTrace> liveToolTraces;

  @override
  State<MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<MessageList> {
  final ScrollController _scroll = ScrollController();

  @override
  void didUpdateWidget(covariant MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messages.length != oldWidget.messages.length ||
        _tailSignature(widget) != _tailSignature(oldWidget)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  String _tailSignature(MessageList list) {
    final tail = list.messages.isEmpty ? '' : list.messages.last.content;
    final liveSig = list.liveToolTraces
        .map((t) => '${t.toolCallId}:${t.status.wire}')
        .join('|');
    return '$tail#$liveSig';
  }

  void _scrollToBottom() {
    if (!mounted || !_scroll.hasClients) return;
    _scroll.animateTo(
      0,
      duration: MaterialMotion.micro,
      curve: MaterialMotion.standard,
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
      return MaterialContentEmpty(
        hint: widget.emptyHint ?? '开始第一条对话',
        subtitle: widget.emptySubtitle,
        illustration: const MaterialEmptyIllustration.noMessages(),
        actionLabel: widget.emptyActionLabel,
        onAction: widget.onEmptyAction,
        secondaryActionLabel: widget.emptySecondaryActionLabel,
        onSecondaryAction: widget.onEmptySecondaryAction,
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
      // 末尾锚定在 offset=0，底部定位不依赖懒加载的总高度估算。
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: items.length + extra,
      itemBuilder: (context, index) {
        final displayIndex = items.length + extra - index - 1;
        if (displayIndex >= items.length) {
          return Align(
            alignment: Alignment.centerLeft,
            child: ToolCallTraceGroup(traces: live),
          );
        }
        final item = items[displayIndex];
        if (item is ChatDisplayToolRound) {
          return Align(
            alignment: Alignment.centerLeft,
            child: ToolCallTraceGroup(traces: item.traces),
          );
        }
        final msgItem = item as ChatDisplayMessage;
        final msg = msgItem.message;
        final canRecall =
            widget.recallEnabled &&
            msg.role == ChatRole.user &&
            msg.id == lastUserId;
        return Align(
          alignment: msg.role == ChatRole.user
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: RepaintBoundary(
            child: MessageBubble(
              key: ValueKey(msg.id),
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
