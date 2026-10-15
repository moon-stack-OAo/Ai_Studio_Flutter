import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';

import 'settings_typography.dart';

class BackupImportDialog extends StatefulWidget {
  const BackupImportDialog({
    super.key,
    required this.payload,
    this.generationBusy = false,
  });

  final DataBackupPayload payload;
  final bool generationBusy;

  @override
  State<BackupImportDialog> createState() => _BackupImportDialogState();
}

class _BackupImportDialogState extends State<BackupImportDialog> {
  bool _importSecrets = false;
  bool _importSkills = true;

  @override
  Widget build(BuildContext context) => ContentDialog(
    title: const Text('导入设置'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '将合并提供商、业务 MCP 与外观设置，并用备份中的会话替换本地会话。'
            '\n导入的本地 stdio 配置将禁用，须在 MCP 设置确认命令后启用。'
            '${widget.generationBusy ? '\n\n检测到进行中的生成，导入前将尝试停止。' : ''}',
          ),
          if (widget.payload.skills != null) ...[
            const SizedBox(height: 14),
            Checkbox(
              checked: _importSkills,
              onChanged: (v) => setState(() => _importSkills = v == true),
              content: Text('合并自定义技能（${widget.payload.skills!.length} 项）'),
            ),
            const SizedBox(height: 6),
            const Text('按 ID 合并：同 ID 更新，新 ID 追加；取消勾选则保留本机技能。'),
          ],
          if (widget.payload.includeSecrets) ...[
            const SizedBox(height: 14),
            Checkbox(
              checked: _importSecrets,
              onChanged: (v) => setState(() => _importSecrets = v == true),
              content: const Text('同时导入密钥（API Key、MCP Token、stdio 环境变量）'),
            ),
            if (_importSecrets) ...[
              const SizedBox(height: 8),
              Text(
                '将用备份中的密钥覆盖本机对应提供商 API Key、MCP Token 与 stdio 环境变量。请确认备份来源可信。',
                style: context.settingsText.caption.copyWith(
                  color: fluentTokensOf(context).danger,
                ),
              ),
            ],
          ] else ...[
            const SizedBox(height: 10),
            Text(
              '此备份不含密钥，本地 API Key、MCP Token 与 stdio 环境变量保持不变。',
              style: context.settingsText.caption,
            ),
          ],
        ],
      ),
    ),
    actions: [
      Button(onPressed: () => Navigator.pop(context), child: const Text('取消')),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          DataBackupImportOptions(
            importSecrets: widget.payload.includeSecrets && _importSecrets,
            importSkills: _importSkills,
          ),
        ),
        child: const Text('导入'),
      ),
    ],
  );
}
