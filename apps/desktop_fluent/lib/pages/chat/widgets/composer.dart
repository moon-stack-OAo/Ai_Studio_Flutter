import 'package:core/core.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../chat_controller.dart';

/// F-Composer：对齐 OpenDesign `fluent-*-chat.html` 底栏输入样式；含 CHAT-ATTACH。
class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.enabled,
    required this.streaming,
    required this.onSend,
    required this.onStop,
    this.visionSupported = false,
    this.draftAttachments = const [],
    this.onPickAttachments,
    this.onDropAttachment,
    this.onRemoveDraftAttachment,
    this.canSendWithDraft,
  });

  final bool enabled;
  final bool streaming;
  final ValueChanged<String> onSend;
  final VoidCallback onStop;

  /// 当前对话模型是否支持视觉（启发式）。
  final bool visionSupported;

  final List<ChatDraftAttachment> draftAttachments;
  final VoidCallback? onPickAttachments;
  final Future<void> Function(String path)? onDropAttachment;
  final ValueChanged<int>? onRemoveDraftAttachment;

  /// 含正文/附图的发送门闩；缺省时退化为 [enabled] + 非空正文。
  final bool Function(String textDraft)? canSendWithDraft;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _focused = false;
  bool _dragging = false;
  bool _textNonEmpty = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
    _controller.addListener(_onTextChanged);
  }

  void _onFocusChange() {
    final next = _focus.hasFocus;
    if (next != _focused) setState(() => _focused = next);
  }

  void _onTextChanged() {
    final next = _controller.text.trim().isNotEmpty;
    if (next != _textNonEmpty) setState(() => _textNonEmpty = next);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _hasDraft => widget.draftAttachments.isNotEmpty;

  bool get _canSubmitContent {
    final gate = widget.canSendWithDraft;
    if (gate != null) return gate(_controller.text);
    if (!widget.enabled) return false;
    return _controller.text.trim().isNotEmpty || _hasDraft;
  }

  void _submit() {
    if (widget.streaming) {
      widget.onStop();
      return;
    }
    if (!_canSubmitContent) return;
    final text = _controller.text;
    widget.onSend(text);
    _controller.clear();
    _focus.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    if (widget.streaming) {
      widget.onStop();
      return KeyEventResult.handled;
    }
    if (!_canSubmitContent) return KeyEventResult.ignored;
    _submit();
    return KeyEventResult.handled;
  }

  Future<void> _handleDrop(DropDoneDetails detail) async {
    final onDrop = widget.onDropAttachment;
    if (onDrop == null || !widget.visionSupported) return;
    if (detail.files.isEmpty) return;
    for (final file in detail.files) {
      final path = file.path.trim();
      if (path.isEmpty) continue;
      await onDrop(path);
      if (widget.draftAttachments.length >= maxChatAttachments) break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    final density =
        UiDensity.fromVisualDensity(FluentTheme.of(context).visualDensity);
    final canType = widget.enabled && !widget.streaming;
    final isDark = tokens.brightness == Brightness.dark;
    final radius = isDark ? 10.0 : 12.0;
    final cardBg = isDark ? tokens.surfaceElevated : tokens.canvas;
    final dropEnabled =
        widget.visionSupported && widget.onDropAttachment != null && canType;
    final highlight = _dragging && dropEnabled;

    final borderColor = highlight
        ? tokens.primary
        : (_focused
            ? Color.lerp(tokens.primary, tokens.border, isDark ? 0.45 : 0.55)!
            : tokens.border);
    final focusRing = highlight
        ? tokens.primary.withValues(alpha: isDark ? 0.22 : 0.16)
        : (_focused
            ? tokens.primary.withValues(alpha: isDark ? 0.22 : 0.16)
            : null);

    final attachTooltip = !widget.visionSupported
        ? '当前模型不支持图片'
        : (widget.draftAttachments.length >= maxChatAttachments
            ? '最多 $maxChatAttachments 张'
            : '附加图片（最多 $maxChatAttachments 张）');
    final canPick = widget.visionSupported &&
        canType &&
        widget.onPickAttachments != null &&
        widget.draftAttachments.length < maxChatAttachments;

    return DropTarget(
      enable: dropEnabled,
      onDragEntered: (_) {
        if (!_dragging) setState(() => _dragging = true);
      },
      onDragExited: (_) {
        if (_dragging) setState(() => _dragging = false);
      },
      onDragDone: (detail) async {
        if (_dragging) setState(() => _dragging = false);
        await _handleDrop(detail);
      },
      child: Container(
        padding: density.composerPadding,
        decoration: BoxDecoration(
          color: tokens.surface,
          border: Border(top: BorderSide(color: tokens.border)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.streaming) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color:
                      tokens.primary.withValues(alpha: isDark ? 0.14 : 0.10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Color.lerp(
                      tokens.primary,
                      tokens.border,
                      isDark ? 0.65 : 0.75,
                    )!,
                  ),
                ),
                child: Row(
                  children: [
                    _PulseDot(color: tokens.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '正在流式输出 · 可随时停止',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Color.lerp(
                            tokens.primary,
                            tokens.ink,
                            isDark ? 0.35 : 0.55,
                          ),
                          fontFamily: tokens.fontFamily,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_hasDraft) ...[
              _DraftAttachmentStrip(
                drafts: widget.draftAttachments,
                tokens: tokens,
                onRemove: canType ? widget.onRemoveDraftAttachment : null,
              ),
              SizedBox(height: density == UiDensity.compact ? 6 : 8),
            ],
            AnimatedContainer(
              duration: FluentMotion.micro,
              curve: FluentMotion.standard,
              padding: density.composerInnerPadding,
              decoration: BoxDecoration(
                color: highlight
                    ? tokens.primary.withValues(alpha: 0.08)
                    : cardBg,
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: borderColor, width: 1),
                boxShadow: focusRing == null
                    ? null
                    : [
                        BoxShadow(
                          color: focusRing,
                          blurRadius: 0,
                          spreadRadius: 3,
                        ),
                      ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Tooltip(
                      message: attachTooltip,
                      child: Semantics(
                        button: true,
                        enabled: canPick,
                        label: '附加图片',
                        excludeSemantics: true,
                        child: HoverButton(
                          onPressed:
                              canPick ? widget.onPickAttachments : null,
                          builder: (context, states) {
                            final hovered = canPick &&
                                (states.isHovered || states.isPressed);
                            final focused = canPick && states.isFocused;
                            final bg = !canPick
                                ? Colors.transparent
                                : hovered
                                    ? tokens.surfaceMuted
                                    : Colors.transparent;
                            final border = !canPick
                                ? Colors.transparent
                                : (hovered || focused)
                                    ? tokens.border
                                    : Colors.transparent;
                            final fg = canPick
                                ? (hovered ? tokens.ink : tokens.inkSecondary)
                                : tokens.inkMuted.withValues(alpha: 0.55);
                            return SizedBox(
                              width: 36,
                              height: 36,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: bg,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: border),
                                ),
                                child: Icon(
                                  FluentIcons.attach,
                                  size: 18,
                                  color: fg,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: density == UiDensity.compact ? 36 : 44,
                        maxHeight: density == UiDensity.compact ? 100 : 120,
                      ),
                      child: Semantics(
                        label: '消息输入',
                        textField: true,
                        child: Focus(
                          onKeyEvent: _onKey,
                          child: TextBox(
                            controller: _controller,
                            focusNode: _focus,
                            enabled: canType,
                            maxLines: null,
                            minLines: 1,
                            placeholder: widget.streaming
                                ? '生成中…'
                                : (highlight
                                    ? '松开以附加图片…'
                                    : (_hasDraft
                                        ? '可空文发送附图 · Enter 发送，Shift+Enter 换行'
                                        : '输入消息…')),
                            style: TextStyle(
                              fontFamily: tokens.fontFamily,
                              fontSize: 14,
                              height: 1.5,
                              color: tokens.ink,
                            ),
                            placeholderStyle: TextStyle(
                              fontFamily: tokens.fontFamily,
                              fontSize: 14,
                              height: 1.5,
                              color: tokens.inkMuted,
                            ),
                            padding: EdgeInsets.fromLTRB(
                              4,
                              density == UiDensity.compact ? 4 : 6,
                              4,
                              density == UiDensity.compact ? 4 : 6,
                            ),
                            unfocusedColor: Colors.transparent,
                            highlightColor: Colors.transparent,
                            decoration: const WidgetStatePropertyAll(
                              BoxDecoration(color: Colors.transparent),
                            ),
                            foregroundDecoration: const WidgetStatePropertyAll(
                              BoxDecoration(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: SizedBox(
                      height: 36,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 72),
                        child: widget.streaming
                            ? Tooltip(
                                message: '停止生成',
                                child: Semantics(
                                  button: true,
                                  label: '停止生成',
                                  excludeSemantics: true,
                                  child: Button(
                                    onPressed: widget.onStop,
                                    style: ButtonStyle(
                                      padding: const WidgetStatePropertyAll(
                                        EdgeInsets.symmetric(horizontal: 14),
                                      ),
                                      backgroundColor:
                                          WidgetStateProperty.resolveWith(
                                        (states) {
                                          if (states.isDisabled) {
                                            return tokens.danger
                                                .withValues(alpha: 0.45);
                                          }
                                          if (states.isPressed ||
                                              states.isHovered) {
                                            return Color.lerp(
                                              tokens.danger,
                                              tokens.ink,
                                              0.12,
                                            )!;
                                          }
                                          return tokens.danger;
                                        },
                                      ),
                                      foregroundColor: WidgetStatePropertyAll(
                                        tokens.onPrimary,
                                      ),
                                      shape: WidgetStatePropertyAll(
                                        RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      '停止',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        fontFamily: tokens.fontFamily,
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : Tooltip(
                                message: '发送（Enter）',
                                child: Semantics(
                                  button: true,
                                  label: '发送消息',
                                  excludeSemantics: true,
                                  child: FilledButton(
                                    onPressed:
                                        _canSubmitContent ? _submit : null,
                                    style: ButtonStyle(
                                      padding: const WidgetStatePropertyAll(
                                        EdgeInsets.symmetric(horizontal: 14),
                                      ),
                                      shape: WidgetStatePropertyAll(
                                        RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      '发送',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        fontFamily: tokens.fontFamily,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: density == UiDensity.compact ? 6 : 8),
            Row(
              children: [
                Flexible(
                  child: Text(
                    widget.streaming
                        ? '流式生成中'
                        : (!widget.visionSupported
                            ? '本地密钥 · 当前模型不支持附图'
                            : (_hasDraft
                                ? '已附加 ${widget.draftAttachments.length}/$maxChatAttachments 张'
                                : '本地密钥 · 无云同步')),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: tokens.inkMuted,
                      fontFamily: tokens.fontFamily,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Enter 发送',
                  style: TextStyle(
                    fontSize: 11,
                    color: tokens.inkMuted,
                    fontFamily: tokens.fontFamily,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DraftAttachmentStrip extends StatelessWidget {
  const _DraftAttachmentStrip({
    required this.drafts,
    required this.tokens,
    this.onRemove,
  });

  final List<ChatDraftAttachment> drafts;
  final FluentTokens tokens;
  final ValueChanged<int>? onRemove;

  static const double _size = 44;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: tokens.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: _size,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: drafts.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final draft = drafts[index];
                  return SizedBox(
                    width: _size,
                    height: _size,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: Container(
                            width: _size,
                            height: _size,
                            decoration: BoxDecoration(
                              color: tokens.canvas,
                              border: Border.all(color: tokens.border),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Image.memory(
                              draft.bytes,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Center(
                                child: Icon(
                                  FluentIcons.photo,
                                  size: 16,
                                  color: tokens.inkMuted,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (onRemove != null)
                          Positioned(
                            top: 1,
                            right: 1,
                            child: Semantics(
                              button: true,
                              label: '移除附图 ${index + 1}',
                              child: GestureDetector(
                                onTap: () => onRemove!(index),
                                child: Container(
                                  width: 16,
                                  height: 16,
                                  decoration: const BoxDecoration(
                                    color: Color(0xB8141413),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    FluentIcons.clear,
                                    size: 8,
                                    color: Color(0xFFFFFFFF),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${drafts.length}/$maxChatAttachments',
            style: TextStyle(
              fontSize: 11,
              color: tokens.inkMuted,
              fontFamily: tokens.fontFamily,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color});

  final Color color;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        return Opacity(
          opacity: 0.35 + 0.65 * (1 - t),
          child: Transform.scale(
            scale: 0.85 + 0.15 * (1 - t),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      },
    );
  }
}
