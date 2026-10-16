import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

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
  bool _followingBottom = true;
  bool _userScrolling = false;
  bool _bottomFrameScheduled = false;
  bool _forceBottom = false;

  @override
  void didUpdateWidget(covariant MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final lastUserId = _lastUserIdIn(widget.messages);
    final sentUserMessage =
        lastUserId != null &&
        lastUserId != _lastUserIdIn(oldWidget.messages) &&
        !oldWidget.messages.any((m) => m.id == lastUserId);
    // 撤回不会被当作主动发送；流式结束、工具轨迹和正文变化均遵循跟随状态。
    if (sentUserMessage || _followingBottom) {
      _scheduleBottom(force: sentUserMessage);
    }
  }

  String? _lastUserIdIn(List<ChatMessage> messages) {
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == ChatRole.user) return messages[i].id;
    }
    return null;
  }

  bool _atBottom(ScrollMetrics metrics) =>
      metrics.pixels <= metrics.minScrollExtent + 1;

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if ((notification is ScrollStartNotification &&
            notification.dragDetails != null) ||
        (notification is UserScrollNotification &&
            notification.direction != ScrollDirection.idle)) {
      // 拖动一开始就取消待执行的定位；滚轮同样通过 UserScroll 通知暂停跟随。
      _userScrolling = true;
      _followingBottom = false;
      _forceBottom = false;
    } else if (notification is ScrollEndNotification ||
        (notification is UserScrollNotification &&
            notification.direction == ScrollDirection.idle)) {
      _userScrolling = false;
      _followingBottom = _atBottom(notification.metrics);
    } else if (notification is ScrollUpdateNotification && !_userScrolling) {
      _followingBottom = _atBottom(notification.metrics);
    }
    return false;
  }

  void _scheduleBottom({bool force = false}) {
    _forceBottom |= force;
    if (force) _followingBottom = true;
    if (_bottomFrameScheduled) return;
    _bottomFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bottomFrameScheduled = false;
      if (!mounted || !_scroll.hasClients) return;
      final force = _forceBottom;
      _forceBottom = false;
      // Theme/ScrollPhysics 重建可替换 position，始终读取当前连接的实例。
      final position = _scroll.position;
      if (!force &&
          (!_followingBottom ||
              _userScrolling ||
              position.isScrollingNotifier.value)) {
        return;
      }
      // reverse 列表本身锚定在 0；delta 无需启动比节流间隔更长的动画。
      if (position.pixels != position.minScrollExtent) {
        position.jumpTo(position.minScrollExtent);
      }
    });
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

    final lastUserId = _lastUserIdIn(widget.messages);

    final items = groupChatMessagesForDisplay(widget.messages);
    final live = widget.liveToolTraces;
    final extra = live.isEmpty ? 0 : 1;
    final keys = <Key>[
      for (final item in items)
        switch (item) {
          ChatDisplayMessage() => ValueKey(('message', item.message.id)),
          ChatDisplayToolRound() => ValueKey((
            'tool-round',
            item.anchorMessageId ?? item.traces.first.toolCallId,
          )),
        },
      if (live.isNotEmpty) const ValueKey('live-tool-traces'),
    ];
    final childIndices = <Key, int>{
      for (var i = 0; i < keys.length; i++) keys[i]: keys.length - i - 1,
    };
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: ListView.builder(
        controller: _scroll,
        // 末尾锚定在 offset=0，底部定位不依赖懒加载的总高度估算。
        reverse: true,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        itemCount: items.length + extra,
        findChildIndexCallback: (key) => childIndices[key],
        itemBuilder: (context, index) {
          final displayIndex = items.length + extra - index - 1;
          final key = keys[displayIndex];
          if (displayIndex >= items.length) {
            return Align(
              key: key,
              alignment: Alignment.centerLeft,
              child: ToolCallTraceGroup(traces: live),
            );
          }
          final item = items[displayIndex];
          if (item is ChatDisplayToolRound) {
            return Align(
              key: key,
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
            key: key,
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
      ),
    );
  }
}
