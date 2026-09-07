import 'package:fluent_ui/fluent_ui.dart';

import 'theme.dart';

/// F-ContentDialog 确认框：统一圆角/边框/危险主按钮。
///
/// 复杂表单弹窗仍可直接用 [ContentDialog]，会继承 [FluentThemeData.dialogTheme]。
Future<bool> showFluentConfirmDialog({
  required BuildContext context,
  required String title,
  String? message,
  Widget? content,
  String cancelLabel = '取消',
  String confirmLabel = '确定',
  bool isDestructive = false,
  bool barrierDismissible = true,
  BoxConstraints constraints = const BoxConstraints(maxWidth: 420),
}) async {
  assert(
    message != null || content != null,
    'showFluentConfirmDialog 需要 message 或 content',
  );
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) {
      final tokens = fluentTokensOf(ctx);
      return ContentDialog(
        constraints: constraints,
        title: Text(title),
        content: content ?? Text(message!),
        actions: [
          Button(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            style: isDestructive
                ? ButtonStyle(
                    backgroundColor: WidgetStatePropertyAll(tokens.danger),
                  )
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
