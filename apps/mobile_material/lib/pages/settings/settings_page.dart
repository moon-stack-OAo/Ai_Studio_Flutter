import 'dart:async';

import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';

import '../../app/theme_controller.dart';
import '../../update/mobile_update_controller.dart';
import 'hidden_portal_page.dart';
import 'settings_about_tab.dart';
import 'settings_appearance_tab.dart';
import 'settings_chat_defaults_tab.dart';
import 'settings_logs_tab.dart';
import 'settings_providers_tab.dart';
import 'settings_skills_tab.dart';

/// Material 设置：默认六 Tab；解锁后追加「实验室」。
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
    this.mcpServerRepository,
    this.mcpSessionFactory,
    this.hiddenPortalPrefs,
    this.skillRepository,
  });

  final ThemeController themeController;
  final SkillRepository? skillRepository;
  final ProviderRepository providerRepository;
  final ChatDefaultsRepository chatDefaultsRepository;
  final AppearanceRepository appearanceRepository;
  final AppLogRepository appLogRepository;
  final DataBackupService dataBackupService;
  final GenerationRuntime generation;
  final int initialTabIndex;
  final MobileUpdateController? updateController;
  final McpServerRepository? mcpServerRepository;
  final McpSessionFactory? mcpSessionFactory;

  final HiddenPortalPrefs? hiddenPortalPrefs;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late final HiddenPortalPrefs _portalPrefs;
  late final SkillRepository _skills;

  static const _baseTabs = <String>['提供商', '对话', '技能', '外观', '日志', '关于'];
  static const _labTabLabel = '实验室';

  List<String> get _tabs => _portalPrefs.unlocked
      ? [..._baseTabs, _labTabLabel]
      : _baseTabs;

  int get _aboutTabIndex => _baseTabs.indexOf('关于');

  @override
  void initState() {
    super.initState();
    _skills = widget.skillRepository ?? SkillRepository(storage: MemorySkillStorage());
    if (!_skills.isLoaded) unawaited(_skills.load().catchError((Object _) {}));
    _portalPrefs = widget.hiddenPortalPrefs ?? HiddenPortalPrefs();
    _portalPrefs.addListener(_onPortalPrefsChanged);
    final initial = widget.initialTabIndex.clamp(0, _baseTabs.length - 1);
    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: initial,
    );
    unawaited(_bootstrapPortalPrefs());
  }

  Future<void> _bootstrapPortalPrefs() async {
    await _portalPrefs.ensureLoaded();
    if (!mounted) return;
    _rebuildTabController();
  }

  void _onPortalPrefsChanged() {
    if (!mounted) return;
    _rebuildTabController();
  }

  void _rebuildTabController() {
    final nextLength = _tabs.length;
    var nextIndex = _tabController.index;
    if (nextIndex >= nextLength) {
      nextIndex = _aboutTabIndex;
    }
    if (_tabController.length == nextLength) {
      if (_tabController.index != nextIndex) {
        _tabController.index = nextIndex;
      }
      setState(() {});
      return;
    }
    final old = _tabController;
    _tabController = TabController(
      length: nextLength,
      vsync: this,
      initialIndex: nextIndex.clamp(0, nextLength - 1),
    );
    old.dispose();
    setState(() {});
  }

  /// 连点切换：返回操作后是否处于解锁态。
  Future<bool> _toggleLab() async {
    return _portalPrefs.toggle();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    unawaited(_portalPrefs.ensureLoaded());
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTabIndex != widget.initialTabIndex) {
      final next = widget.initialTabIndex.clamp(0, _tabController.length - 1);
      if (_tabController.index != next) {
        _tabController.index = next;
      }
    }
  }

  @override
  void dispose() {
    _portalPrefs.removeListener(_onPortalPrefsChanged);
    _tabController.dispose();
    if (widget.skillRepository == null) _skills.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    final tabs = _tabs;

    return Scaffold(
      backgroundColor: tokens.canvas,
      appBar: AppBar(
        title: const Text('设置'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: tokens.primaryPressed,
          unselectedLabelColor: tokens.inkMuted,
          indicatorColor: tokens.primary,
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: tokens.border,
          labelPadding: const EdgeInsets.symmetric(horizontal: 18),
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
            for (final label in tabs) Tab(text: label, height: 44),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          SettingsProvidersTab(
            repository: widget.providerRepository,
            mcpServerRepository: widget.mcpServerRepository,
            mcpSessionFactory: widget.mcpSessionFactory,
          ),
          SettingsChatDefaultsTab(repository: widget.chatDefaultsRepository),
          SettingsSkillsTab(repository: _skills),
          SettingsAppearanceTab(themeController: widget.themeController),
          SettingsLogsTab(repository: widget.appLogRepository),
          SettingsAboutTab(
            skillRepository: _skills,
            dataBackupService: widget.dataBackupService,
            themeController: widget.themeController,
            generation: widget.generation,
            updateController: widget.updateController,
            onUnlockHiddenPortal: _toggleLab,
          ),
          if (_portalPrefs.unlocked) const HiddenPortalPage(),
        ],
      ),
    );
  }
}
