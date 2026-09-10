import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';

import '../pages/chat/widgets/markdown_host.dart';

/// 更新确认结果：跳过 / 稍后 / 下载安装。
enum UpdatePromptAction { skip, later, install }

/// FB-UPDATE / M-UpdatePrompt：发现新版本确认框（跳过 / 稍后 / 下载并安装）。
///
/// scrim 关闭等价「稍后」。iOS 主按钮禁用，正文用 [iosMessage] 说明非 Store 分发。
Future<UpdatePromptAction?> showUpdatePromptDialog({
  required BuildContext context,
  required UpdateCheckResult result,
  bool isIos = false,
  String iosMessage = '请通过内测渠道获取新版本（非 App Store）',
}) {
  final version = normalizeVersion(result.latestVersion);
  final current = normalizeVersion(result.currentVersion);
  final notes = prepareUpdateNotes(result.notes);

  return showDialog<UpdatePromptAction>(
    context: context,
    barrierDismissible: true,
    builder: (dialogCtx) {
      final tokens = materialTokensOf(dialogCtx);
      final bodyStyle = TextStyle(
        fontSize: 14,
        height: 1.45,
        color: tokens.inkSecondary,
        fontFamily: tokens.fontFamily,
        fontFamilyFallback: kMaterialFontFamilyFallback,
      );

      return AlertDialog(
        title: Semantics(
          header: true,
          child: Text('发现新版本 v$version'),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isIos
                  ? '当前版本 v$current。$iosMessage'
                  : '当前版本 v$current。是否下载并安装更新？'
                      '将下载 APK 并校验签名后提示安装。不上架 · 侧载清单。'
                      '请确认已允许「安装未知应用」。',
              style: bodyStyle,
            ),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: tokens.surfaceMuted,
                    borderRadius: BorderRadius.circular(12),
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
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogCtx, UpdatePromptAction.skip),
            child: const Text('跳过此版本'),
          ),
          OutlinedButton(
            onPressed: () =>
                Navigator.pop(dialogCtx, UpdatePromptAction.later),
            child: const Text('稍后'),
          ),
          if (isIos)
            const FilledButton(
              onPressed: null,
              child: Text('下载并安装'),
            )
          else
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
