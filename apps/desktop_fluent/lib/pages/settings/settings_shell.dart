import 'dart:async';

import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../app/theme_controller.dart';
import '../../shell/app_section.dart';
import '../../update/update_controller.dart';
import 'hidden_portal_page.dart';
import 'settings_about_page.dart';
import 'settings_appearance_page.dart';
import 'settings_chat_defaults_page.dart';
import 'settings_logs_page.dart';
import 'settings_mcp_page.dart';
import 'settings_providers_page.dart';

class SettingsShell extends StatefulWidget {
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
    this.mcpServerRepository,
    this.mcpSessionFactory,
    this.hiddenPortalPrefs,
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
  final McpServerRepository? mcpServerRepository;
  final McpSessionFactory? mcpSessionFactory;
  final HiddenPortalPrefs? hiddenPortalPrefs;

  @override
  State<SettingsShell> createState() => _SettingsShellState();
}

class _SettingsShellState extends State<SettingsShell> {
  late final HiddenPortalPrefs _portalPrefs;

  @override
  void initState() {
    super.initState();
    _portalPrefs = widget.hiddenPortalPrefs ?? HiddenPortalPrefs();
    _portalPrefs.addListener(_onPortalPrefsChanged);
    unawaited(_portalPrefs.ensureLoaded());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 进入/停留设置时按 TTL 过期（不在 build 内 notify）。
    unawaited(_portalPrefs.ensureLoaded());
  }

  void _onPortalPrefsChanged() {
    if (!mounted) return;
    if (!_portalPrefs.unlocked && widget.category == SettingsCategory.lab) {
      widget.onCategoryChanged(SettingsCategory.about);
    }
    setState(() {});
  }

  @override
  void dispose() {
    _portalPrefs.removeListener(_onPortalPrefsChanged);
    super.dispose();
  }

  List<SettingsCategory> get _categories {
    if (_portalPrefs.unlocked) {
      return [...SettingsCategory.visibleByDefault, SettingsCategory.lab];
    }
    return SettingsCategory.visibleByDefault;
  }

  /// 连点切换：返回操作后是否处于解锁态。
  Future<bool> _toggleLab() async {
    return _portalPrefs.toggle();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    final density =
        UiDensity.fromVisualDensity(FluentTheme.of(context).visualDensity);
    final categories = _categories;
    final selected = categories.contains(widget.category)
        ? widget.category
        : SettingsCategory.about;

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
                        for (final item in categories)
                          _SettingsCatTile(
                            category: item,
                            selected: item == selected,
                            tileVPad: density.settingsCatTileVertical,
                            onPressed: () => widget.onCategoryChanged(item),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: _buildContent(selected)),
        ],
      ),
    );
  }

  Widget _buildContent(SettingsCategory category) {
    return switch (category) {
      SettingsCategory.providers => SettingsProvidersPage(
          repository: widget.providerRepository,
        ),
      SettingsCategory.mcp => _buildMcpPage(),
      SettingsCategory.chatDefaults => SettingsChatDefaultsPage(
          repository: widget.chatDefaultsRepository,
        ),
      SettingsCategory.appearance => SettingsAppearancePage(
          themeController: widget.themeController,
        ),
      SettingsCategory.logs => SettingsLogsPage(
          repository: widget.appLogRepository,
        ),
      SettingsCategory.about => SettingsAboutPage(
          appearanceRepository: widget.appearanceRepository,
          dataBackupService: widget.dataBackupService,
          themeController: widget.themeController,
          generation: widget.generation,
          updateController: widget.updateController,
          onUnlockHiddenPortal: _toggleLab,
        ),
      SettingsCategory.lab => const HiddenPortalPage(),
    };
  }

  Widget _buildMcpPage() {
    final repo = widget.mcpServerRepository;
    final factory = widget.mcpSessionFactory;
    if (repo == null || factory == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('MCP 尚未在本机初始化。'),
        ),
      );
    }
    return SettingsMcpPage(
      repository: repo,
      sessionFactory: factory,
    );
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
