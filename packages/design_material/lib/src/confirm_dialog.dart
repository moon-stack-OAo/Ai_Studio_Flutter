import 'package:flutter/material.dart';

import 'theme.dart';

/// M-ConfirmDialog：统一 AlertDialog 确认框（危险操作主按钮用 danger）。
///
/// 复杂表单弹窗仍可直接用 [AlertDialog]，会继承 [ThemeData.dialogTheme]。
Future<bool> showMaterialConfirmDialog({
  required BuildContext context,
  required String title,
  String? message,
  Widget? content,
  String cancelLabel = '取消',
  String confirmLabel = '确定',
  bool isDestructive = false,
  bool barrierDismissible = true,
}) async {
  assert(
    message != null || content != null,
    'showMaterialConfirmDialog 需要 message 或 content',
  );
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) {
      final tokens = materialTokensOf(ctx);
      return AlertDialog(
        title: Text(title),
        content: content ?? Text(message!),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            style: isDestructive
                ? FilledButton.styleFrom(backgroundColor: tokens.danger)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result == true;
}
