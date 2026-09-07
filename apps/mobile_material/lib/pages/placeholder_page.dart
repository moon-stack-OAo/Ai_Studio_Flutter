import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';

import '../app/theme_controller.dart';
import '../shell/app_section.dart';

/// P2-A 占位页：对话 / 生图 / 生视频 / 设置。
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({
    super.key,
    required this.section,
    this.themeController,
  });

  final AppSection section;
  final ThemeController? themeController;

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    final isSettings = section == AppSection.settings;

    return Scaffold(
      backgroundColor: tokens.canvas,
      appBar: AppBar(
        title: Text(section.label),
        actions: [
          if (isSettings && themeController != null)
            IconButton(
              tooltip: '切换主题',
              onPressed: () => themeController!.cycleLightDark(),
              icon: Icon(
                themeController!.preference == ThemePreference.dark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  section.label,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: tokens.ink,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: tokens.border,
                      style: BorderStyle.solid,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'M-${section.name} · ${section.capabilityId}',
                    style: TextStyle(
                      fontSize: 11,
                      color: tokens.inkMuted,
                    ).withMonoFont(tokens),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'P2-A 占位 · 后续接入能力页',
                  style: TextStyle(color: tokens.inkSecondary, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                if (isSettings && themeController != null) ...[
                  const SizedBox(height: 24),
                  FilledButton.tonal(
                    onPressed: () => themeController!.cycleLightDark(),
                    child: Text(
                      '切换为${themeController!.preference.toggled.label}',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
