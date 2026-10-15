import 'package:core/core.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// 桌面输入区的全局技能摘要；所有组合逻辑由 core 提供。
class SkillSummary extends StatelessWidget {
  const SkillSummary({
    super.key,
    required this.repository,
    required this.target,
    this.prompt,
    this.enabled = true,
    this.onManage,
  });

  final SkillRepository repository;
  final SkillTarget target;
  final String? prompt;
  final bool enabled;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: repository,
      builder: (context, _) {
        final skills = repository.snapshotFor(target);
        final finalPrompt = prompt == null
            ? null
            : composeSkillPrompt(prompt: prompt!.trim(), skills: skills).trim();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Button(
              onPressed: enabled
                  ? () => showSkillDetails(
                      context,
                      skills: skills,
                      title: '${target.label}生效技能',
                      finalPrompt: finalPrompt,
                      onManage: onManage,
                    )
                  : null,
              child: Text(
                skills.isEmpty
                    ? '技能：未启用 · 管理技能'
                    : '技能 ${skills.length}：${skills.map((s) => s.name).join('、')}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            if (prompt != null)
              Expander(
                header: const Text('最终提示词预览', style: TextStyle(fontSize: 12)),
                content: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: SingleChildScrollView(
                    child: SelectableText(finalPrompt!),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class SkillHistoryButton extends StatelessWidget {
  const SkillHistoryButton({super.key, required this.skills, this.finalPrompt});

  final List<SkillSnapshot> skills;
  final String? finalPrompt;

  @override
  Widget build(BuildContext context) {
    if (skills.isEmpty && finalPrompt == null) return const SizedBox.shrink();
    return Button(
      onPressed: () => showSkillDetails(
        context,
        skills: skills,
        finalPrompt: finalPrompt,
        title: '本次生成的技能快照',
      ),
      child: const Text('查看技能快照', style: TextStyle(fontSize: 11)),
    );
  }
}

Future<void> showSkillDetails(
  BuildContext context, {
  required List<SkillSnapshot> skills,
  required String title,
  String? finalPrompt,
  VoidCallback? onManage,
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => ContentDialog(
      title: Text(title),
      constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (skills.isEmpty) const Text('当前没有生效的自定义技能。'),
            for (final skill in skills) ...[
              Text(
                skill.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              if (skill.prompt.isNotEmpty) ...[
                const Text('提示词'),
                SelectableText(skill.prompt),
                const SizedBox(height: 8),
              ],
              if (skill.rules.isNotEmpty) ...[
                const Text('规则'),
                SelectableText(skill.rules),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 12),
            ],
            if (finalPrompt != null) ...[
              const Text(
                '最终提示词',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              SelectableText(finalPrompt),
            ],
          ],
        ),
      ),
      actions: [
        if (onManage != null)
          Button(
            onPressed: () {
              Navigator.of(ctx).pop();
              onManage();
            },
            child: const Text('管理技能'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}
