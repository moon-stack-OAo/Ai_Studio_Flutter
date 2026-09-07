import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

/// F-Composer：对齐 OpenDesign `fluent-*-chat.html` 底栏输入样式。
class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.enabled,
    required this.streaming,
    required this.onSend,
    required this.onStop,
  });

  final bool enabled;
  final bool streaming;
  final ValueChanged<String> onSend;
  final VoidCallback onStop;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    final next = _focus.hasFocus;
    if (next != _focused) setState(() => _focused = next);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.streaming) {
      widget.onStop();
      return;
    }
    if (!widget.enabled) return;
    final text = _controller.text;
    if (text.trim().isEmpty) return;
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
    if (!widget.enabled) return KeyEventResult.ignored;
    _submit();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    final canType = widget.enabled && !widget.streaming;
    final isDark = tokens.brightness == Brightness.dark;
    final radius = isDark ? 10.0 : 12.0;
    final cardBg = isDark ? tokens.surfaceElevated : tokens.canvas;

    final borderColor = _focused
        ? Color.lerp(tokens.primary, tokens.border, isDark ? 0.45 : 0.55)!
        : tokens.border;
    final focusRing = _focused
        ? tokens.primary.withValues(alpha: isDark ? 0.22 : 0.16)
        : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: tokens.primary.withValues(alpha: isDark ? 0.14 : 0.10),
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
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? const Color(0xFFBFDBFE)
                            : tokens.inkSecondary,
                        fontFamily: tokens.fontFamily,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: borderColor),
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
                Expanded(
                  // OD textarea: min-height 44 / max-height 120
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: 44,
                      maxHeight: 120,
                    ),
                    child: Focus(
                      onKeyEvent: _onKey,
                      child: TextBox(
                        controller: _controller,
                        focusNode: _focus,
                        enabled: canType,
                        maxLines: null,
                        minLines: 2,
                        placeholder: widget.streaming
                            ? '生成中…'
                            : '输入消息… Enter 发送，Shift+Enter 换行',
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
                        padding: EdgeInsets.zero,
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
                const SizedBox(width: 10),
                // OD .send-stop: height 36 / min-width 72
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 72,
                    minHeight: 36,
                  ),
                  child: SizedBox(
                    height: 36,
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
                                          const Color(0xFF000000),
                                          0.12,
                                        )!;
                                      }
                                      return tokens.danger;
                                    },
                                  ),
                                  foregroundColor:
                                      const WidgetStatePropertyAll(
                                    Colors.white,
                                  ),
                                  shape: WidgetStatePropertyAll(
                                    RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
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
                                onPressed: widget.enabled ? _submit : null,
                                style: ButtonStyle(
                                  padding: const WidgetStatePropertyAll(
                                    EdgeInsets.symmetric(horizontal: 14),
                                  ),
                                  shape: WidgetStatePropertyAll(
                                    RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
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
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                widget.streaming ? '流式生成中' : '本地密钥 · 无云同步',
                style: TextStyle(
                  fontSize: 11,
                  color: tokens.inkMuted,
                  fontFamily: tokens.fontFamily,
                ),
              ),
              const Spacer(),
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
