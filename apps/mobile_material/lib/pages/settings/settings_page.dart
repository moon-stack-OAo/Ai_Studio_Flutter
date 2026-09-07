import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';

import '../../app/theme_controller.dart';
import '../../update/mobile_update_controller.dart';
import 'settings_about_tab.dart';
import 'settings_appearance_tab.dart';
import 'settings_chat_defaults_tab.dart';
import 'settings_logs_tab.dart';
import 'settings_providers_tab.dart';

/// Material 设置：五 Tab（提供商 | 对话 | 外观 | 日志 | 关于）。
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.themeController,
    required this.providerRepository,
    required this.chatDefaultsRepository,
    required this.appearanceRepository,
    required this.appLogRepository,
    required this.dataBackupService,
    required this.generation,
    this.initialTabIndex = 0,
    this.updateController,
  });

  final ThemeController themeController;
  final ProviderRepository providerRepository;
  final ChatDefaultsRepository chatDefaultsRepository;
  final AppearanceRepository appearanceRepository;
  final AppLogRepository appLogRepository;
  final DataBackupService dataBackupService;
  final GenerationRuntime generation;
  final int initialTabIndex;
  final MobileUpdateController? updateController;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const _tabs = <String>['提供商', '对话', '外观', '日志', '关于'];

  @override
  void initState() {
    super.initState();
    final initial = widget.initialTabIndex.clamp(0, _tabs.length - 1);
    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: initial,
    );
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTabIndex != widget.initialTabIndex) {
      final next = widget.initialTabIndex.clamp(0, _tabs.length - 1);
      if (_tabController.index != next) {
        _tabController.index = next;
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);

    return Scaffold(
      backgroundColor: tokens.canvas,
      appBar: AppBar(
        title: const Text('设置'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: false,
          labelColor: tokens.primaryPressed,
          unselectedLabelColor: tokens.inkMuted,
          indicatorColor: tokens.primary,
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: tokens.border,
          labelPadding: EdgeInsets.zero,
          labelStyle: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFamily: tokens.fontFamily,
          ),
          unselectedLabelStyle: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            fontFamily: tokens.fontFamily,
          ),
          tabs: [
            for (final label in _tabs) Tab(text: label, height: 44),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          SettingsProvidersTab(repository: widget.providerRepository),
          SettingsChatDefaultsTab(repository: widget.chatDefaultsRepository),
          SettingsAppearanceTab(themeController: widget.themeController),
          SettingsLogsTab(repository: widget.appLogRepository),
          SettingsAboutTab(
            dataBackupService: widget.dataBackupService,
            themeController: widget.themeController,
            generation: widget.generation,
            updateController: widget.updateController,
          ),
        ],
      ),
    );
  }
}
