import 'package:flutter/material.dart';

/// Material 短动效时长（可打断、不挡操作）。
abstract final class MaterialMotion {
  static const Duration sectionSwitch = Duration(milliseconds: 140);
  static const Duration listAppear = Duration(milliseconds: 160);
  static const Duration lightbox = Duration(milliseconds: 200);
  static const Duration pageRoute = Duration(milliseconds: 220);
  static const Duration micro = Duration(milliseconds: 120);

  static const Curve standard = Curves.easeOut;
}

/// 短 fade + 轻微上滑；用于会话列表等二级页。
Route<T> materialFadeSlideRoute<T>({
  required WidgetBuilder builder,
  Duration duration = MaterialMotion.pageRoute,
  Offset beginOffset = const Offset(0.04, 0),
}) {
  return PageRouteBuilder<T>(
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: MaterialMotion.standard,
        reverseCurve: Curves.easeIn,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: beginOffset,
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}
