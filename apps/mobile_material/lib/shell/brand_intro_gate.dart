import 'dart:async';

import 'package:design_material/design_material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// M-BrandIntro（SHELL-BRAND-INTRO）：冷启动短品牌首屏，可跳过。
///
/// [ready] 为 false 时保持覆层（可点按标记跳过，但等就绪后再淡出），
/// 避免底下壳层未挂载时过早拆除。
class BrandIntroGate extends StatefulWidget {
  const BrandIntroGate({
    super.key,
    required this.child,
    this.ready,
    this.displayDuration = const Duration(milliseconds: 900),
    this.fadeDuration = const Duration(milliseconds: 280),
  });

  final Widget child;

  /// `null` 视为已就绪。为 `false` 时不拆除品牌覆层。
  final ValueListenable<bool>? ready;
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
  bool _minElapsed = false;
  bool _userSkip = false;

  bool get _isReady => widget.ready?.value ?? true;

  @override
  void initState() {
    super.initState();
    widget.ready?.addListener(_onReadyChanged);
    _autoTimer = Timer(widget.displayDuration, () {
      _minElapsed = true;
      _tryDismiss();
    });
  }

  @override
  void didUpdateWidget(BrandIntroGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ready != widget.ready) {
      oldWidget.ready?.removeListener(_onReadyChanged);
      widget.ready?.addListener(_onReadyChanged);
      _tryDismiss();
    }
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    widget.ready?.removeListener(_onReadyChanged);
    super.dispose();
  }

  void _onReadyChanged() => _tryDismiss();

  void _dismiss() {
    _userSkip = true;
    _tryDismiss();
  }

  void _tryDismiss() {
    if (_dismissing || !_layerMounted) return;
    if (!_isReady) return;
    if (!_minElapsed && !_userSkip) return;
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
    final tokens = materialTokensOf(context);
    final isDark = tokens.brightness == Brightness.dark;
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: tokens.canvas,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
    );

    return Positioned.fill(
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlayStyle,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _dismiss,
          child: Semantics(
            button: true,
            label: '品牌首屏，轻触跳过',
            child: AnimatedOpacity(
              opacity: _opacity,
              duration: widget.fadeDuration,
              curve: Curves.easeOut,
              onEnd: _onFadeEnd,
              child: ColoredBox(
                color: tokens.canvas,
                child: SafeArea(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 88,
                          height: 88,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: tokens.surface,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: tokens.border),
                            boxShadow: [
                              BoxShadow(
                                color: tokens.ink.withValues(alpha: 0.10),
                                blurRadius: 28,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Image.asset(
                            'assets/logo.png',
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'AI Studio',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.01,
                            color: tokens.ink,
                            fontFamily: tokens.fontFamily,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '对话 · 生图 · 生视频',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: tokens.inkMuted,
                            fontFamily: tokens.fontFamily,
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
