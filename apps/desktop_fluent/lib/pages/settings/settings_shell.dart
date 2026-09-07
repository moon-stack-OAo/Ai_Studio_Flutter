import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../app/theme_controller.dart';
import '../../shell/app_section.dart';
import '../../update/update_controller.dart';
import 'settings_about_page.dart';
import 'settings_appearance_page.dart';
import 'settings_chat_defaults_page.dart';
import 'settings_logs_page.dart';
import 'settings_providers_page.dart';

class SettingsShell extends StatelessWidget {
  const SettingsShell({
    super.key,
    required this.category,
    required this.onCategoryChanged,
    required this.themeController,
    required this.appearanceRepository,
    required this.providerRepository,
    required this.chatDefaultsRepository,
    required this.appLogRepository,
    required this.dataBackupService,
    required this.generation,
    this.updateController,
  });

  final SettingsCategory category;
  final ValueChanged<SettingsCategory> onCategoryChanged;
  final ThemeController themeController;
  final AppearanceRepository appearanceRepository;
  final ProviderRepository providerRepository;
  final ChatDefaultsRepository chatDefaultsRepository;
  final AppLogRepository appLogRepository;
  final DataBackupService dataBackupService;
  final GenerationRuntime generation;
  final UpdateController? updateController;

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    final density =
        UiDensity.fromVisualDensity(FluentTheme.of(context).visualDensity);
    return FocusTraversalGroup(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: tokens.settingsCatWidth,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tokens.surface,
                border: Border(right: BorderSide(color: tokens.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      density == UiDensity.compact ? 10 : 14,
                      16,
                      density == UiDensity.compact ? 6 : 10,
                    ),
                    child: Text(
                      '设置',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: tokens.inkSecondary,
                        fontFamily: tokens.fontFamily,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                      children: [
                        for (final item in SettingsCategory.values)
                          _SettingsCatTile(
                            category: item,
                            selected: item == category,
                            tileVPad: density.settingsCatTileVertical,
                            onPressed: () => onCategoryChanged(item),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return switch (category) {
      SettingsCategory.providers => SettingsProvidersPage(
          repository: providerRepository,
        ),
      SettingsCategory.chatDefaults => SettingsChatDefaultsPage(
          repository: chatDefaultsRepository,
        ),
      SettingsCategory.appearance => SettingsAppearancePage(
          themeController: themeController,
        ),
      SettingsCategory.logs => SettingsLogsPage(
          repository: appLogRepository,
        ),
      SettingsCategory.about => SettingsAboutPage(
          appearanceRepository: appearanceRepository,
          dataBackupService: dataBackupService,
          themeController: themeController,
          generation: generation,
          updateController: updateController,
        ),
    };
  }
}

class _SettingsCatTile extends StatelessWidget {
  const _SettingsCatTile({
    required this.category,
    required this.selected,
    required this.tileVPad,
    required this.onPressed,
  });

  final SettingsCategory category;
  final bool selected;
  final double tileVPad;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    final bg = selected
        ? Color.lerp(tokens.primary, tokens.surface, 0.86)!
        : Colors.transparent;
    final fg = selected ? tokens.ink : tokens.inkSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Semantics(
        button: true,
        selected: selected,
        label: '${category.label}，${category.description}',
        excludeSemantics: true,
        child: Button(
          onPressed: onPressed,
          style: ButtonStyle(
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 12, vertical: tileVPad),
            ),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (selected) return bg;
              if (states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)) {
                return tokens.ink.withValues(alpha: 0.05);
              }
              return Colors.transparent;
            }),
            foregroundColor: WidgetStatePropertyAll(fg),
            shape: WidgetStateProperty.resolveWith((states) {
              final focused = states.contains(WidgetState.focused);
              return RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: focused
                    ? BorderSide(color: tokens.primary.withValues(alpha: 0.55))
                    : BorderSide.none,
              );
            }),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: fg,
                    fontFamily: tokens.fontFamily,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  category.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: tokens.inkMuted,
                    fontFamily: tokens.fontFamily,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
