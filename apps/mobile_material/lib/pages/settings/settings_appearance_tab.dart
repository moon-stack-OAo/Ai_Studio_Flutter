import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';

import '../../app/theme_controller.dart';
import '../../widgets/back_to_top_host.dart';
import 'widgets/settings_section.dart';

class SettingsAppearanceTab extends StatelessWidget {
  const SettingsAppearanceTab({super.key, required this.themeController});

  final ThemeController themeController;

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    final density = UiDensity.fromVisualDensity(
      Theme.of(context).visualDensity,
    );
    final cardPad = density.settingsCardPadding;
    final formGap = density.settingsFormGap;
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        final selected = themeController.preference;
        return BackToTopHost(
          builder: (context, scroll) => ListView(
            controller: scroll,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              SettingsSectionCard(
                child: Padding(
                  padding: EdgeInsets.all(cardPad),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SettingsSectionHeading(
                        title: '主题',
                        icon: Icons.palette_outlined,
                      ),
                      SizedBox(height: formGap),
                      SegmentedButton<ThemePreference>(
                        segments: [
                          for (final pref in ThemePreference.values)
                            ButtonSegment(value: pref, label: Text(pref.label)),
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
              SizedBox(height: formGap - 2),
              SettingsSectionCard(
                child: Padding(
                  padding: EdgeInsets.all(cardPad),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SettingsSectionHeading(
                        title: '字号与密度',
                        icon: Icons.text_fields_rounded,
                      ),
                      SizedBox(height: formGap),
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
                      SizedBox(height: formGap),
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
                      SizedBox(height: formGap - 2),
                      Text(
                        '紧凑：列表更密、Composer 更贴、底栏略矮；舒适：行距与表单项更松。移动默认紧凑；触控主操作 ≥ 48dp。',
                        style: TextStyle(
                          fontSize: 12,
                          color: tokens.inkMuted,
                          fontFamily: tokens.fontFamily,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
