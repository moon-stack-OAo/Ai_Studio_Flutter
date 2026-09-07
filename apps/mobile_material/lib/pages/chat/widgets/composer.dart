import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';

/// M-Composer：底栏输入；IME 由壳藏 Nav + Scaffold resize 抬起。
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

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    final canType = widget.enabled && !widget.streaming;
    final isDark = tokens.brightness == Brightness.dark;
    final imeVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final bottomSafe = MediaQuery.paddingOf(context).bottom;
    final padBottom = 8.0 + (imeVisible ? 0.0 : bottomSafe * 0.15);

    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, padBottom),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.streaming) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: tokens.primary.withValues(alpha: isDark ? 0.14 : 0.10),
                borderRadius: BorderRadius.circular(10),
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
                      '流式输出中 · 点停止可中断',
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  enabled: canType,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: widget.streaming ? '生成中…' : '输入消息…',
                    filled: true,
                    fillColor: isDark ? tokens.surfaceElevated : tokens.canvas,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: tokens.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: tokens.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: tokens.primary),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: tokens.border),
                    ),
                  ),
                  style: TextStyle(
                    fontFamily: tokens.fontFamily,
                    fontSize: 14,
                    height: 1.45,
                    color: tokens.ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 48,
                height: 48,
                child: widget.streaming
                    ? Tooltip(
                        message: '停止生成',
                        child: Semantics(
                          button: true,
                          label: '停止生成',
                          excludeSemantics: true,
                          child: FilledButton(
                            onPressed: widget.onStop,
                            style: FilledButton.styleFrom(
                              backgroundColor: tokens.danger,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(48, 48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Icon(Icons.stop_rounded, size: 22),
                          ),
                        ),
                      )
                    : Tooltip(
                        message: '发送',
                        child: Semantics(
                          button: true,
                          label: '发送消息',
                          excludeSemantics: true,
                          child: FilledButton(
                            onPressed: widget.enabled ? _submit : null,
                            style: FilledButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(48, 48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Icon(Icons.send_rounded, size: 20),
                          ),
                        ),
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
