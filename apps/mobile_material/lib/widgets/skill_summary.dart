import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../pages/settings/settings_skills_tab.dart';

class SkillSummary extends StatelessWidget {
  const SkillSummary({
    super.key,
    required this.repository,
    required this.target,
    this.prompt,
    this.enabled = true,
  });

  final SkillRepository repository;
  final SkillTarget target;
  final String? prompt;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: repository,
      builder: (context, _) {
        final skills = repository.snapshotFor(target);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextButton.icon(
              style: TextButton.styleFrom(alignment: Alignment.centerLeft),
              onPressed: enabled
                  ? () => showSkillDetails(
                      context,
                      skills: skills,
                      repository: repository,
                      target: target,
                      draftPrompt: prompt,
                    )
                  : null,
              icon: const Icon(Icons.auto_awesome_outlined, size: 18),
              label: Text(
                skills.isEmpty
                    ? '自定义技能 · 未启用 · 管理'
                    : '生效技能：${skills.map((s) => s.name).join('、')}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (prompt != null)
              ExpansionTile(
                enabled: enabled,
                title: const Text('最终提示词预览', style: TextStyle(fontSize: 12)),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  SelectableText(
                    composeSkillPrompt(prompt: prompt!.trim(), skills: skills),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}

class AppliedSkillsButton extends StatelessWidget {
  const AppliedSkillsButton({
    super.key,
    required this.skills,
    this.finalPrompt,
  });

  final List<SkillSnapshot> skills;
  final String? finalPrompt;

  @override
  Widget build(BuildContext context) {
    if (skills.isEmpty && finalPrompt == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () =>
            showSkillDetails(context, skills: skills, finalPrompt: finalPrompt),
        icon: const Icon(Icons.auto_awesome_outlined, size: 16),
        label: const Text('查看当次技能与提示词'),
      ),
    );
  }
}

Future<void> showSkillDetails(
  BuildContext context, {
  required List<SkillSnapshot> skills,
  String? finalPrompt,
  SkillRepository? repository,
  SkillTarget? target,
  String? draftPrompt,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      if (repository != null && target != null) {
        return ListenableBuilder(
          listenable: repository,
          builder: (ctx, _) {
            final current = repository.snapshotFor(target);
            return _SkillDetailsContent(
              skills: current,
              finalPrompt: draftPrompt == null
                  ? null
                  : composeSkillPrompt(
                      prompt: draftPrompt.trim(),
                      skills: current,
                    ),
              onManage: () {
                Navigator.of(ctx).pop();
                openSkillManagement(context, repository);
              },
            );
          },
        );
      }
      return _SkillDetailsContent(skills: skills, finalPrompt: finalPrompt);
    },
  );
}

class _SkillDetailsContent extends StatelessWidget {
  const _SkillDetailsContent({
    required this.skills,
    this.finalPrompt,
    this.onManage,
  });

  final List<SkillSnapshot> skills;
  final String? finalPrompt;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext ctx) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      onManage == null ? '当次技能快照' : '当前生效技能',
                      style: Theme.of(ctx).textTheme.titleLarge,
                    ),
                  ),
                  if (onManage != null)
                    TextButton(onPressed: onManage, child: const Text('管理技能')),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (skills.isEmpty) const Text('没有生效的自定义技能'),
                  for (final s in skills)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              s.name,
                              style: Theme.of(ctx).textTheme.titleMedium,
                            ),
                            if (s.prompt.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              const Text('提示词'),
                              SelectableText(s.prompt),
                            ],
                            if (s.rules.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              const Text('规则'),
                              SelectableText(s.rules),
                            ],
                          ],
                        ),
                      ),
                    ),
                  if (finalPrompt != null) ...[
                    const SizedBox(height: 16),
                    const Text('最终提示词'),
                    const SizedBox(height: 8),
                    SelectableText(finalPrompt!),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
