import 'dart:io';

import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../pages/chat/widgets/markdown_host.dart';

/// 更新确认结果：跳过 / 稍后 / 下载安装。
enum UpdatePromptAction { skip, later, install }

String updateInstallPlatformLabel() {
  if (Platform.isMacOS) return 'macOS';
  if (Platform.isWindows) return 'Windows';
  return '桌面';
}

/// 对齐旧版：发现新版本确认框（跳过 / 稍后 / 下载并安装）。
Future<UpdatePromptAction?> showUpdatePromptDialog({
  required BuildContext context,
  required UpdateCheckResult result,
  bool installing = false,
}) {
  final version = result.latestVersion ?? '';
  final current = result.currentVersion;
  final notes = prepareUpdateNotes(result.notes);
  final platform = updateInstallPlatformLabel();

  return showDialog<UpdatePromptAction>(
    context: context,
    barrierDismissible: true,
    builder: (dialogCtx) {
      final tokens = fluentTokensOf(dialogCtx);
      final titleStyle = TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: tokens.ink,
        fontFamily: tokens.fontFamily,
        fontFamilyFallback: kFluentFontFamilyFallback,
      );
      final bodyStyle = TextStyle(
        fontSize: 13,
        height: 1.45,
        color: tokens.inkSecondary,
        fontFamily: tokens.fontFamily,
        fontFamilyFallback: kFluentFontFamilyFallback,
      );
      final actionStyle = TextStyle(
        fontFamily: tokens.fontFamily,
        fontFamilyFallback: kFluentFontFamilyFallback,
      );

      return ContentDialog(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        title: Text('发现新版本 v$version', style: titleStyle),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前版本 v$current。是否下载并安装更新？'
                  '将下载 $platform 安装包并校验签名；安装完成后将退出并启动安装器。',
                  style: bodyStyle,
                ),
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  MarkdownHost(data: notes, compact: true),
                ],
              ],
            ),
          ),
        ),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Button(
                onPressed: installing
                    ? null
                    : () => Navigator.pop(dialogCtx, UpdatePromptAction.skip),
                child: Text('跳过此版本', style: actionStyle),
              ),
              const SizedBox(width: 8),
              Button(
                onPressed: installing
                    ? null
                    : () => Navigator.pop(dialogCtx, UpdatePromptAction.later),
                child: Text('稍后', style: actionStyle),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: installing
                    ? null
                    : () =>
                        Navigator.pop(dialogCtx, UpdatePromptAction.install),
                child: installing
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: ProgressRing(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text('下载中…', style: actionStyle),
                        ],
                      )
                    : Text('下载并安装', style: actionStyle),
              ),
            ],
          ),
        ],
      );
    },
  ).then((value) => value ?? UpdatePromptAction.later);
}
