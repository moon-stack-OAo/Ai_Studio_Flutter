import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../../image/widgets/image_lightbox.dart';
import 'markdown_host.dart';
import 'tool_call_trace_card.dart';

class MessageBubble extends StatefulWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.onRecall,
    this.recallEnabled = false,
    this.hideToolCallsStrip = false,
  });

  final ChatMessage message;
  final VoidCallback? onRecall;
  final bool recallEnabled;

  /// 工具轮已由列表聚合卡展示时，隐藏气泡内「调用了工具」条。
  final bool hideToolCallsStrip;

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  final FlyoutController _flyout = FlyoutController();
  bool _hovered = false;
  bool _focused = false;

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

  Future<void> _openAttachmentLightbox(int index) async {
    final refs = message.attachments;
    if (refs.isEmpty) return;
    final start = index.clamp(0, refs.length - 1);
    await ImageLightbox.show(
      context,
      ref: refs[start],
      refs: refs,
      initialIndex: start,
      source: ImageLightboxSource.attachment,
      loadBytes: () => _loadAttachmentBytes(refs[start]),
      loadBytesFor: _loadAttachmentBytes,
    );
  }

  Future<Uint8List?> _loadAttachmentBytes(ImageRef ref) async {
    try {
      if (ref.type == ImageRefType.file) {
        final file = File(ref.src);
        if (await file.exists()) return file.readAsBytes();
      }
      if (ref.type == ImageRefType.b64 && ref.src.isNotEmpty) {
        return Uint8List.fromList(base64Decode(ref.src));
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    final isUser = message.role == ChatRole.user;
    final isTool = message.role == ChatRole.tool;
    final isDark = tokens.brightness == Brightness.dark;
    final Color bg;
    if (isUser) {
      bg = tokens.surface;
    } else if (isTool) {
      bg = Color.lerp(tokens.surface, tokens.canvas, 0.4)!;
    } else if (isDark) {
      bg = tokens.surfaceElevated;
    } else {
      bg = Color.lerp(tokens.surface, tokens.surfaceElevated, 0.55)!;
    }
    final border = tokens.border;
    final roleColor = isUser
        ? tokens.primaryPressed
        : (isTool ? tokens.inkMuted : tokens.inkMuted);
    final showActions =
        (_hovered || _focused) && !message.streaming && !isTool;
    final canRecall = widget.recallEnabled && widget.onRecall != null;
    final attachments = isUser ? message.attachments : const <ImageRef>[];
    final hasAttachments = attachments.isNotEmpty;
    final bodyText = message.content.isEmpty && message.streaming
        ? ''
        : (message.content.isEmpty && message.error
            ? (message.errorMessage ?? '出错了')
            : message.content);
    final showUserText = isUser && bodyText.isNotEmpty;
    final roleLabel = isUser ? '你' : (isTool ? '工具' : '助手');

    return FocusableActionDetector(
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: FlyoutTarget(
          controller: _flyout,
          child: GestureDetector(
            onSecondaryTapUp: isTool
                ? null
                : (details) => _showContextMenu(details.globalPosition),
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
                          roleLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.04 * 11,
                            color: roleColor,
                            fontFamily: tokens.fontFamily,
                          ),
                        ),
                        if (!isUser && !isTool) ...[
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(isDark ? 10 : 12),
                      border: Border.all(color: border),
                    ),
                    child: isUser
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (hasAttachments) ...[
                                _ChatAttachmentThumbs(
                                  refs: attachments,
                                  tokens: tokens,
                                  onTap: _openAttachmentLightbox,
                                ),
                                if (showUserText) const SizedBox(height: 10),
                              ],
                              if (showUserText)
                                SelectableText(
                                  bodyText,
                                  textWidthBasis: TextWidthBasis.longestLine,
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.65,
                                    color: message.error
                                        ? tokens.danger
                                        : tokens.ink,
                                    fontFamily: tokens.fontFamily,
                                  ),
                                ),
                            ],
                          )
                        : isTool
                            ? ToolResultBubbleBody(message: message)
                            : _AssistantBody(
                                message: message,
                                tokens: tokens,
                                hideToolCallsStrip: widget.hideToolCallsStrip,
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
                    duration: FluentMotion.micro,
                    curve: FluentMotion.standard,
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
      ),
    );
  }
}

/// 对话气泡附图缩略（CHAT-ATTACH；独立于生图 TURN-REF）。
class _ChatAttachmentThumbs extends StatelessWidget {
  const _ChatAttachmentThumbs({
    required this.refs,
    required this.tokens,
    this.onTap,
  });

  final List<ImageRef> refs;
  final FluentTokens tokens;
  final ValueChanged<int>? onTap;

  static const double _size = 72;

  @override
  Widget build(BuildContext context) {
    final shown = refs.length > maxChatAttachments
        ? refs.sublist(0, maxChatAttachments)
        : refs;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.end,
      children: [
        for (var index = 0; index < shown.length; index++)
          Semantics(
            button: onTap != null,
            label: '附图 ${index + 1}',
            child: GestureDetector(
              onTap: onTap == null ? null : () => onTap!(index),
              child: MouseRegion(
                cursor: onTap == null
                    ? SystemMouseCursors.basic
                    : SystemMouseCursors.click,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: _size,
                    height: _size,
                    decoration: BoxDecoration(
                      color: tokens.canvas,
                      border: Border.all(color: tokens.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _ChatAttachmentThumb(ref: shown[index]),
                  ),
                ),
              ),
            ),
          ),
        Text(
          '附图',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
            color: tokens.inkMuted,
            fontFamily: tokens.fontFamily,
          ),
        ),
      ],
    );
  }
}

class _ChatAttachmentThumb extends StatefulWidget {
  const _ChatAttachmentThumb({required this.ref});

  final ImageRef ref;

  @override
  State<_ChatAttachmentThumb> createState() => _ChatAttachmentThumbState();
}

class _ChatAttachmentThumbState extends State<_ChatAttachmentThumb> {
  Uint8List? _bytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _ChatAttachmentThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ref.src != widget.ref.src ||
        oldWidget.ref.type != widget.ref.type) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _bytes = null;
    });
    try {
      if (widget.ref.type == ImageRefType.url) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      if (widget.ref.type == ImageRefType.file) {
        final f = File(widget.ref.src);
        if (await f.exists()) {
          final b = await f.readAsBytes();
          if (mounted) {
            setState(() {
              _bytes = b;
              _loading = false;
            });
          }
          return;
        }
      }
      if (widget.ref.type == ImageRefType.b64 && widget.ref.src.isNotEmpty) {
        final b = Uint8List.fromList(base64Decode(widget.ref.src));
        if (mounted) {
          setState(() {
            _bytes = b;
            _loading = false;
          });
        }
        return;
      }
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    if (_loading) {
      return const Center(child: ProgressRing(strokeWidth: 2));
    }
    if (_bytes != null && _bytes!.isNotEmpty) {
      return Image.memory(_bytes!, fit: BoxFit.cover);
    }
    if (widget.ref.type == ImageRefType.url) {
      return Image.network(
        widget.ref.src,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Center(
          child: Icon(FluentIcons.photo, size: 18, color: tokens.inkMuted),
        ),
      );
    }
    return Center(
      child: Icon(FluentIcons.photo, size: 18, color: tokens.inkMuted),
    );
  }
}

class _AssistantBody extends StatelessWidget {
  const _AssistantBody({
    required this.message,
    required this.tokens,
    this.hideToolCallsStrip = false,
  });

  final ChatMessage message;
  final FluentTokens tokens;
  final bool hideToolCallsStrip;

  @override
  Widget build(BuildContext context) {
    final emptyStreaming = message.content.isEmpty &&
        message.streaming &&
        !message.hasToolCalls;
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
        if (message.hasToolCalls && !hideToolCallsStrip)
          ToolCallsInvokedStrip(toolCalls: message.toolCalls),
        if (data.isNotEmpty || message.error)
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
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: HoverButton(
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
      ),
    );
  }
}
