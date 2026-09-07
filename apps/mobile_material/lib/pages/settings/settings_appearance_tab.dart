import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';

import '../../app/theme_controller.dart';

class SettingsAppearanceTab extends StatelessWidget {
  const SettingsAppearanceTab({
    super.key,
    required this.themeController,
  });

  final ThemeController themeController;

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        final selected = themeController.preference;
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '主题',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: tokens.ink,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<ThemePreference>(
                      segments: [
                        for (final pref in ThemePreference.values)
                          ButtonSegment(
                            value: pref,
                            label: Text(pref.label),
                          ),
                      ],
                      selected: {selected},
                      onSelectionChanged: (set) {
                        if (set.isEmpty) return;
                        themeController.setPreference(set.first);
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '字号与密度',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: tokens.ink,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<AppFontScale>(
                      key: ValueKey(themeController.fontScale),
                      initialValue: themeController.fontScale,
                      decoration: const InputDecoration(labelText: '字号'),
                      items: [
                        for (final scale in AppFontScale.values)
                          DropdownMenuItem(
                            value: scale,
                            child: Text(
                              scale == AppFontScale.standard
                                  ? '${scale.label}（默认）'
                                  : scale.label,
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) themeController.setFontScale(v);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<UiDensity>(
                      key: ValueKey(themeController.density),
                      initialValue: themeController.density,
                      decoration: const InputDecoration(labelText: '密度'),
                      items: [
                        for (final dens in UiDensity.values)
                          DropdownMenuItem(
                            value: dens,
                            child: Text(
                              dens == UiDensity.compact
                                  ? '${dens.label}（默认）'
                                  : dens.label,
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) themeController.setDensity(v);
                      },
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '紧凑：列表更密、底栏略矮；舒适：行距更松。移动默认紧凑；触控主操作 ≥ 48dp。',
                      style: TextStyle(fontSize: 12, color: tokens.inkMuted),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
