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

/// FB-UPDATE / F-UpdatePrompt：发现新版本确认框（跳过 / 稍后 / 下载并安装）。
///
/// H1：不保留 `installing` 态——全仓无调用方传入；下载进度由关于页卡片展示，
/// 弹窗关闭后由壳层 InfoBar 提示即可。scrim 关闭等价「稍后」。
Future<UpdatePromptAction?> showUpdatePromptDialog({
  required BuildContext context,
  required UpdateCheckResult result,
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
      final bodyStyle = TextStyle(
        fontSize: 13,
        height: 1.55,
        color: tokens.inkSecondary,
        fontFamily: tokens.fontFamily,
        fontFamilyFallback: kFluentFontFamilyFallback,
      );

      return ContentDialog(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
        title: Semantics(
          header: true,
          child: Text('发现新版本 v$version'),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '当前版本 v$current。是否下载并安装更新？'
              '将下载 $platform 安装包并校验签名；安装完成后将退出并启动安装器。'
              '不上架 · 直链分发。',
              style: bodyStyle,
            ),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: tokens.surfaceMuted,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: tokens.border),
                  ),
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: SingleChildScrollView(
                    child: MarkdownHost(data: notes, compact: true),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          Button(
            onPressed: () => Navigator.pop(dialogCtx, UpdatePromptAction.skip),
            child: const Text('跳过此版本'),
          ),
          Button(
            onPressed: () => Navigator.pop(dialogCtx, UpdatePromptAction.later),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogCtx, UpdatePromptAction.install),
            child: const Text('下载并安装'),
          ),
        ],
      );
    },
  ).then((value) => value ?? UpdatePromptAction.later);
}
