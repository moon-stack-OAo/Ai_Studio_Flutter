import 'package:flutter/material.dart';

/// M-BackHost（NAV-BACK）：系统返回 / 边缘滑动 / 顶栏返回统一先关最上层。
class BackHost extends StatelessWidget {
  const BackHost({super.key, required this.child});

  final Widget child;

  /// 与系统返回同一套栈语义（Dialog / BottomSheet / 本页路由）。
  static Future<bool> pop(BuildContext context) {
    return Navigator.of(context).maybePop();
  }

  static Widget leadingButton(
    BuildContext context, {
    String tooltip = '返回',
    IconData icon = Icons.arrow_back,
  }) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon),
      onPressed: () => pop(context),
    );
  }

  static Widget closeButton(
    BuildContext context, {
    String tooltip = '关闭',
    IconData icon = Icons.close,
  }) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon),
      onPressed: () => pop(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: child,
    );
  }
}
