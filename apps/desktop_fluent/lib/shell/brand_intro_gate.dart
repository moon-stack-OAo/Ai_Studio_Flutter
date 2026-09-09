import 'dart:async';

import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

/// F-BrandIntro（SHELL-BRAND-INTRO）：冷启动短品牌首屏，可跳过。
class BrandIntroGate extends StatefulWidget {
  const BrandIntroGate({
    super.key,
    required this.child,
    this.displayDuration = const Duration(milliseconds: 900),
    this.fadeDuration = const Duration(milliseconds: 280),
  });

  final Widget child;
  final Duration displayDuration;
  final Duration fadeDuration;

  @override
  State<BrandIntroGate> createState() => _BrandIntroGateState();
}

class _BrandIntroGateState extends State<BrandIntroGate> {
  bool _layerMounted = true;
  double _opacity = 1;
  Timer? _autoTimer;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _autoTimer = Timer(widget.displayDuration, _dismiss);
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  void _dismiss() {
    if (_dismissing || !_layerMounted) return;
    _dismissing = true;
    _autoTimer?.cancel();
    setState(() => _opacity = 0);
  }

  void _onFadeEnd() {
    if (_opacity > 0 || !_layerMounted) return;
    setState(() => _layerMounted = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_layerMounted) _buildOverlay(context),
      ],
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final tokens = fluentTokensOf(context);
    return Positioned.fill(
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            _dismiss();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _dismiss,
          child: Semantics(
            button: true,
            label: '品牌首屏，点击或按任意键跳过',
            child: AnimatedOpacity(
              opacity: _opacity,
              duration: widget.fadeDuration,
              curve: Curves.easeOut,
              onEnd: _onFadeEnd,
              child: ColoredBox(
                color: tokens.canvas,
                child: DefaultTextStyle.merge(
                  style: const TextStyle(decoration: TextDecoration.none),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: tokens.surface,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: tokens.border),
                            boxShadow: [
                              BoxShadow(
                                color: tokens.ink.withValues(alpha: 0.10),
                                blurRadius: 32,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: Image.asset(
                            'assets/logo.png',
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'AI Studio',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.02,
                            color: tokens.ink,
                            fontFamily: tokens.fontFamily,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '对话 · 生图 · 生视频',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            letterSpacing: 0.02,
                            color: tokens.inkMuted,
                            fontFamily: tokens.fontFamily,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
