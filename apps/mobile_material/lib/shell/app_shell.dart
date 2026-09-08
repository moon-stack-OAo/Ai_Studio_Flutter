import 'dart:async';

import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';

import '../app/theme_controller.dart';
import '../pages/chat/chat_page.dart';
import '../pages/image/image_page.dart';
import '../pages/settings/settings_page.dart';
import '../pages/video/video_page.dart';
import '../update/mobile_update_controller.dart';
import 'app_section.dart';
import 'update_banner.dart';

/// Material 壳：Scaffold + 四入口 NavigationBar；IME 升起时随 viewInsets 收起底栏。
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.themeController,
    required this.providerRepository,
    required this.sessionRepository,
    required this.imageSessionRepository,
    required this.videoSessionRepository,
    required this.chatDefaultsRepository,
    required this.appearanceRepository,
    required this.appLogRepository,
    required this.dataBackupService,
    required this.generation,
    this.chatClient,
    this.imageClient,
    this.videoClient,
    this.updateController,
    this.updateBannerPrefs,
    this.startupUpdateCheckDelay = const Duration(milliseconds: 800),
  });

  final ThemeController themeController;
  final ProviderRepository providerRepository;
  final ChatSessionRepository sessionRepository;
  final ImageSessionRepository imageSessionRepository;
  final VideoSessionRepository videoSessionRepository;
  final ChatDefaultsRepository chatDefaultsRepository;
  final AppearanceRepository appearanceRepository;
  final AppLogRepository appLogRepository;
  final DataBackupService dataBackupService;
  final GenerationRuntime generation;
  final OpenAiCompatibleChatClient? chatClient;
  final OpenAiCompatibleImageClient? imageClient;
  final OpenAiCompatibleVideoClient? videoClient;
  final MobileUpdateController? updateController;
  final UpdateBannerPrefs? updateBannerPrefs;
  final Duration startupUpdateCheckDelay;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppSection _section = AppSection.chat;
  int _settingsTabIndex = 0;
  double _paneOpacity = 1;
  late final UpdateBannerPrefs _bannerPrefs;
  late final MobileUpdateController _updater;
  late final bool _ownsUpdater;
  String? _bannerVersion;
  String? _bannerSubtitle;
  bool _startupCheckStarted = false;
  Timer? _startupCheckTimer;

  static const _sections = <AppSection>[
    AppSection.chat,
    AppSection.image,
    AppSection.video,
    AppSection.settings,
  ];

  @override
  void initState() {
    super.initState();
    _bannerPrefs = widget.updateBannerPrefs ?? UpdateBannerPrefs();
    _ownsUpdater = widget.updateController == null;
    _updater = widget.updateController ?? MobileUpdateController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduleStartupUpdateCheck();
    });
  }

  @override
  void dispose() {
    _startupCheckTimer?.cancel();
    if (_ownsUpdater) _updater.dispose();
    super.dispose();
  }

  Widget _navIcon(AppSection section, {required bool selected}) {
    return switch (section) {
      AppSection.chat => NavIcons.chat(selected: selected),
      AppSection.image => NavIcons.image(selected: selected),
      AppSection.video => NavIcons.video(selected: selected),
      AppSection.settings => NavIcons.settings(selected: selected),
    };
  }

  void _openProviders() {
    setState(() {
      _section = AppSection.settings;
      _settingsTabIndex = 0;
    });
  }

  void _onDestinationSelected(int index) {
    final next = AppSection.values[index];
    if (next == _section) return;
    setState(() {
      _section = next;
      _paneOpacity = 0.72;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _paneOpacity = 1);
    });
  }

  void _scheduleStartupUpdateCheck() {
    if (_startupCheckStarted) return;
    _startupCheckStarted = true;
    final delay = widget.startupUpdateCheckDelay;
    if (delay <= Duration.zero) {
      unawaited(_runStartupUpdateCheck());
      return;
    }
    _startupCheckTimer = Timer(delay, () {
      unawaited(_runStartupUpdateCheck());
    });
  }

  Future<void> _runStartupUpdateCheck() async {
    if (!mounted) return;
    if (_updater.isChecking || _updater.isDownloading) return;

    try {
      final result = await _updater.checkForUpdate();
      if (!mounted) return;
      if (result.status != UpdateCheckStatus.available) return;
      final version = result.latestVersion;
      if (version == null || version.trim().isEmpty) return;
      if (!await _bannerPrefs.shouldShowFor(version)) return;
      if (!mounted) return;
      setState(() {
        _bannerVersion = normalizeVersion(version);
        _bannerSubtitle = _updater.isIos
            ? MobileUpdateController.iosNonStoreMessage
            : null;
      });
    } catch (e) {
      try {
        await widget.appLogRepository.append(
          level: AppLogLevel.warn,
          source: AppLogSources.updater,
          message: '启动检查更新失败（已静默）：$e',
        );
      } catch (_) {}
    }
  }

  Future<void> _dismissBanner() async {
    final version = _bannerVersion;
    if (version != null) {
      await _bannerPrefs.dismissVersion(version);
    }
    if (!mounted) return;
    setState(() {
      _bannerVersion = null;
      _bannerSubtitle = null;
    });
  }

  void _goUpdateFromBanner() {
    setState(() {
      _bannerVersion = null;
      _bannerSubtitle = null;
      _section = AppSection.settings;
      _settingsTabIndex = 4;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    final density =
        UiDensity.fromVisualDensity(Theme.of(context).visualDensity);
    final viewInsetsBottom = MediaQuery.viewInsetsOf(context).bottom;
    // 全面屏手势条 / 三键导航：NavigationBar 自身 SafeArea 会叠在 theme height 之下，
    // 槽位必须含 viewPadding，否则收起键盘时底栏提前弹出并可能裁切手势区。
    final systemBottom = MediaQuery.viewPaddingOf(context).bottom;
    final navHeight = density.navigationBarHeight;
    final navSlotHeight = navHeight + systemBottom;
    // 与键盘高度同相位收起，避免 bottomNavigationBar: null 瞬时跳变。
    final navVisibleFactor =
        (1.0 - (viewInsetsBottom / navSlotHeight).clamp(0.0, 1.0)).toDouble();
    final selectedIndex = AppSection.values.indexOf(_section);
    final bannerVersion = _bannerVersion;

    return Scaffold(
      backgroundColor: tokens.canvas,
      // 键盘抬起只由内页 Scaffold 负责，避免双层 resize 叠跳。
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (bannerVersion != null)
              UpdateBanner(
                version: bannerVersion,
                subtitle: _bannerSubtitle,
                onGoUpdate: _goUpdateFromBanner,
                onLater: () => unawaited(_dismissBanner()),
              ),
            Expanded(
              child: AnimatedOpacity(
                opacity: _paneOpacity,
                duration: MaterialMotion.sectionSwitch,
                curve: MaterialMotion.standard,
                child: IndexedStack(
                  index: selectedIndex,
                  children: [
                    for (final section in AppSection.values)
                      if (section == AppSection.chat)
                        ChatPage(
                          providerRepository: widget.providerRepository,
                          sessionRepository: widget.sessionRepository,
                          chatDefaultsRepository: widget.chatDefaultsRepository,
                          appLogRepository: widget.appLogRepository,
                          generation: widget.generation,
                          chatClient: widget.chatClient,
                          onOpenProviders: _openProviders,
                        )
                      else if (section == AppSection.image)
                        ImagePage(
                          providerRepository: widget.providerRepository,
                          sessionRepository: widget.imageSessionRepository,
                          chatDefaultsRepository: widget.chatDefaultsRepository,
                          appLogRepository: widget.appLogRepository,
                          generation: widget.generation,
                          chatClient: widget.chatClient,
                          imageClient: widget.imageClient,
                          onOpenProviders: _openProviders,
                        )
                      else if (section == AppSection.video)
                        VideoPage(
                          providerRepository: widget.providerRepository,
                          sessionRepository: widget.videoSessionRepository,
                          chatDefaultsRepository: widget.chatDefaultsRepository,
                          appLogRepository: widget.appLogRepository,
                          generation: widget.generation,
                          chatClient: widget.chatClient,
                          videoClient: widget.videoClient,
                          onOpenProviders: _openProviders,
                        )
                      else if (section == AppSection.settings)
                        SettingsPage(
                          themeController: widget.themeController,
                          providerRepository: widget.providerRepository,
                          chatDefaultsRepository: widget.chatDefaultsRepository,
                          appearanceRepository: widget.appearanceRepository,
                          appLogRepository: widget.appLogRepository,
                          dataBackupService: widget.dataBackupService,
                          generation: widget.generation,
                          initialTabIndex: _settingsTabIndex,
                          updateController: _updater,
                        )
                      else
                        const SizedBox.shrink(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: navVisibleFactor,
          child: IgnorePointer(
            ignoring: navVisibleFactor < 0.05,
            child: SizedBox(
              height: navSlotHeight,
              child: NavigationBar(
                selectedIndex: selectedIndex,
                onDestinationSelected: _onDestinationSelected,
                destinations: [
                  for (final section in _sections)
                    NavigationDestination(
                      icon: _navIcon(section, selected: false),
                      selectedIcon: _navIcon(section, selected: true),
                      label: section.label,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
