import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import 'markdown_host.dart';

class MessageBubble extends StatefulWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.onRecall,
    this.recallEnabled = false,
  });

  final ChatMessage message;
  final VoidCallback? onRecall;
  final bool recallEnabled;

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  final FlyoutController _flyout = FlyoutController();
  bool _hovered = false;

  ChatMessage get message => widget.message;

  @override
  void dispose() {
    _flyout.dispose();
    super.dispose();
  }

  String get _plainText {
    if (message.content.isEmpty && message.error) {
      return message.errorMessage ?? '出错了';
    }
    return message.content;
  }

  Future<void> _copy() async {
    final text = _plainText;
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    displayInfoBar(
      context,
      builder: (context, close) {
        return InfoBar(
          title: const Text('已复制'),
          severity: InfoBarSeverity.success,
          onClose: close,
        );
      },
    );
  }

  Future<void> _showContextMenu(Offset globalPosition) async {
    final navBox =
        Navigator.of(context).context.findRenderObject() as RenderBox?;
    if (navBox == null) return;
    final position = navBox.globalToLocal(globalPosition);
    await _flyout.showFlyout<void>(
      position: position,
      barrierDismissible: true,
      dismissWithEsc: true,
      builder: (ctx) {
        return MenuFlyout(
          items: [
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.copy, size: 14),
              text: const Text('复制'),
              onPressed: () {
                Navigator.of(ctx).pop();
                _copy();
              },
            ),
            if (widget.recallEnabled && widget.onRecall != null)
              MenuFlyoutItem(
                leading: const Icon(FluentIcons.undo, size: 14),
                text: const Text('撤回'),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  widget.onRecall!();
                },
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    final isUser = message.role == ChatRole.user;
    final isDark = tokens.brightness == Brightness.dark;
    final Color bg;
    if (isUser) {
      bg = tokens.surface;
    } else if (isDark) {
      bg = tokens.surfaceElevated;
    } else {
      bg = Color.lerp(tokens.surface, tokens.surfaceElevated, 0.55)!;
    }
    final border = tokens.border;
    final roleColor = isUser ? tokens.primaryPressed : tokens.inkMuted;
    final showActions = _hovered && !message.streaming;
    final canRecall = widget.recallEnabled && widget.onRecall != null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: FlyoutTarget(
        controller: _flyout,
        child: GestureDetector(
          onSecondaryTapUp: (details) =>
              _showContextMenu(details.globalPosition),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            // 短消息随内容宽度；外层 Align 左右分侧 + maxWidth:780 约束长内容
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.only(
                    bottom: 6,
                    left: isUser ? 0 : 2,
                    right: isUser ? 2 : 0,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isUser ? '你' : '助手',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.04 * 11,
                          color: roleColor,
                          fontFamily: tokens.fontFamily,
                        ),
                      ),
                      if (!isUser) ...[
                        Builder(
                          builder: (_) {
                            final meta = formatChatMessageMeta(
                              model: message.model,
                              latencyMs: message.latencyMs,
                              streaming: message.streaming,
                            );
                            if (meta == null || meta.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text(
                                meta,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: tokens.inkMuted,
                                ).withMonoFont(tokens),
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(isDark ? 10 : 12),
                    border: Border.all(color: border),
                  ),
                  child: isUser
                      ? SelectableText(
                          message.content.isEmpty && message.streaming
                              ? ''
                              : (message.content.isEmpty && message.error
                                  ? (message.errorMessage ?? '出错了')
                                  : message.content),
                          textWidthBasis: TextWidthBasis.longestLine,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.65,
                            color:
                                message.error ? tokens.danger : tokens.ink,
                            fontFamily: tokens.fontFamily,
                          ),
                        )
                      : _AssistantBody(
                          message: message,
                          tokens: tokens,
                        ),
                ),
                if (message.stopped)
                  Padding(
                    padding: EdgeInsets.only(
                      top: 4,
                      left: isUser ? 0 : 2,
                      right: isUser ? 2 : 0,
                    ),
                    child: Text(
                      '已停止',
                      style: TextStyle(
                        fontSize: 11,
                        color: tokens.inkMuted,
                        fontFamily: tokens.fontFamily,
                      ),
                    ),
                  ),
                if (message.error &&
                    message.errorMessage != null &&
                    message.content.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(
                      top: 4,
                      left: isUser ? 0 : 2,
                      right: isUser ? 2 : 0,
                    ),
                    child: Text(
                      message.errorMessage!,
                      style: TextStyle(
                        fontSize: 11,
                        color: tokens.danger,
                        fontFamily: tokens.fontFamily,
                      ),
                    ),
                  ),
                AnimatedOpacity(
                  opacity: showActions ? 1 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: IgnorePointer(
                    ignoring: !showActions,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ActionChip(
                            label: '复制',
                            onPressed: _copy,
                            tokens: tokens,
                          ),
                          if (canRecall) ...[
                            const SizedBox(width: 4),
                            _ActionChip(
                              label: '撤回',
                              onPressed: widget.onRecall!,
                              tokens: tokens,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AssistantBody extends StatelessWidget {
  const _AssistantBody({
    required this.message,
    required this.tokens,
  });

  final ChatMessage message;
  final FluentTokens tokens;

  @override
  Widget build(BuildContext context) {
    final emptyStreaming =
        message.content.isEmpty && message.streaming;
    final data = emptyStreaming
        ? ''
        : (message.content.isEmpty && message.error
            ? (message.errorMessage ?? '出错了')
            : message.content);

    if (emptyStreaming) {
      return const _StreamCursor();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MarkdownHost(
          data: data,
          error: message.error,
        ),
        if (message.streaming && message.content.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: _StreamCursor(),
          ),
      ],
    );
  }
}

class _StreamCursor extends StatefulWidget {
  const _StreamCursor();

  @override
  State<_StreamCursor> createState() => _StreamCursorState();
}

class _StreamCursorState extends State<_StreamCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    return FadeTransition(
      opacity: Tween<double>(begin: 0.15, end: 1).animate(_ctrl),
      child: Container(
        width: 7,
        height: 14,
        margin: const EdgeInsets.only(left: 2),
        color: tokens.primary,
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.label,
    required this.onPressed,
    required this.tokens,
  });

  final String label;
  final VoidCallback onPressed;
  final FluentTokens tokens;

  @override
  Widget build(BuildContext context) {
    return HoverButton(
      onPressed: onPressed,
      cursor: SystemMouseCursors.click,
      builder: (context, states) {
        final hovered = states.isHovered || states.isPressed;
        return Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: hovered ? tokens.surfaceMuted : tokens.surface,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: tokens.border),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: hovered ? tokens.ink : tokens.inkSecondary,
              fontFamily: tokens.fontFamily,
            ),
          ),
        );
      },
    );
  }
}
