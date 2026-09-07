import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../app/theme_controller.dart';

class SettingsAppearancePage extends StatelessWidget {
  const SettingsAppearancePage({super.key, required this.themeController});

  final ThemeController themeController;

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    final density =
        UiDensity.fromVisualDensity(FluentTheme.of(context).visualDensity);
    final sectionPad = density.settingsSectionPadding;
    final formGap = density.settingsFormGap;
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        final selected = themeController.preference;
        return ColoredBox(
          color: tokens.canvas,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
            children: [
              Text(
                '外观',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: tokens.ink,
                  fontFamily: tokens.fontFamily,
                ),
              ),
              SizedBox(height: formGap + 6),
              Container(
                padding: EdgeInsets.all(sectionPad),
                decoration: BoxDecoration(
                  color: tokens.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: tokens.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '主题',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: tokens.inkSecondary,
                        fontFamily: tokens.fontFamily,
                      ),
                    ),
                    SizedBox(height: formGap),
                    Row(
                      children: [
                        for (final pref in ThemePreference.values) ...[
                          if (pref != ThemePreference.values.first)
                            const SizedBox(width: 8),
                          Expanded(
                            child: _ThemeSegButton(
                              label: pref.label,
                              selected: selected == pref,
                              onPressed: () =>
                                  themeController.setPreference(pref),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: formGap + 2),
              Container(
                padding: EdgeInsets.all(sectionPad),
                decoration: BoxDecoration(
                  color: tokens.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: tokens.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '字号与密度',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: tokens.inkSecondary,
                        fontFamily: tokens.fontFamily,
                      ),
                    ),
                    SizedBox(height: formGap),
                    _LabeledField(
                      label: '字号',
                      child: ComboBox<AppFontScale>(
                        value: themeController.fontScale,
                        isExpanded: true,
                        items: [
                          for (final scale in AppFontScale.values)
                            ComboBoxItem(
                              value: scale,
                              child: Text(scale.label),
                            ),
                        ],
                        onChanged: (v) {
                          if (v != null) themeController.setFontScale(v);
                        },
                      ),
                    ),
                    SizedBox(height: formGap),
                    _LabeledField(
                      label: '密度',
                      child: ComboBox<UiDensity>(
                        value: themeController.density,
                        isExpanded: true,
                        items: [
                          for (final dens in UiDensity.values)
                            ComboBoxItem(
                              value: dens,
                              child: Text(
                                dens == UiDensity.comfortable
                                    ? '${dens.label}（默认）'
                                    : dens.label,
                              ),
                            ),
                        ],
                        onChanged: (v) {
                          if (v != null) themeController.setDensity(v);
                        },
                      ),
                    ),
                    SizedBox(height: formGap - 2),
                    Text(
                      '舒适：列表与窗格更疏；紧凑：会话行、Composer 与设置侧栏更紧。桌面默认舒适。',
                      style: TextStyle(
                        fontSize: 12,
                        color: tokens.inkMuted,
                        fontFamily: tokens.fontFamily,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: tokens.inkSecondary,
            fontFamily: tokens.fontFamily,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _ThemeSegButton extends StatelessWidget {
  const _ThemeSegButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    final border = selected
        ? Color.lerp(tokens.primary, tokens.border, 0.45)!
        : tokens.border;
    final bg = selected
        ? Color.lerp(tokens.primary, tokens.surface, 0.86)!
        : tokens.surfaceMuted;
    final fg = selected ? tokens.primaryPressed : tokens.inkSecondary;

    return Button(
      onPressed: onPressed,
      style: ButtonStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        backgroundColor: WidgetStatePropertyAll(bg),
        foregroundColor: WidgetStatePropertyAll(fg),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: border),
          ),
        ),
      ),
      child: SizedBox(
        height: 34,
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: fg,
              fontFamily: tokens.fontFamily,
            ),
          ),
        ),
      ),
    );
  }
}
