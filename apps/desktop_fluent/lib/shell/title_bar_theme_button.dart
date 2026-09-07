import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../app/theme_controller.dart';

/// 标题栏主题入口：点击在浅色 ↔ 深色间循环。
class TitleBarThemeButton extends StatelessWidget {
  const TitleBarThemeButton({
    super.key,
    required this.controller,
  });

  final ThemeController controller;

  IconData _iconFor(ThemePreference pref) {
    return switch (pref) {
      ThemePreference.light => FluentIcons.sunny,
      ThemePreference.dark => FluentIcons.clear_night,
    };
  }

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final pref = controller.preference;
        final next = pref.toggled;
        return Tooltip(
          message: '切换主题（当前${pref.label} → ${next.label}）',
          child: Semantics(
            button: true,
            label: '切换主题，当前${pref.label}',
            excludeSemantics: true,
            child: IconButton(
              onPressed: controller.cycleLightDark,
              icon: Icon(
                _iconFor(pref),
                size: 14,
                color: tokens.inkSecondary,
              ),
            ),
          ),
        );
      },
    );
  }
}
