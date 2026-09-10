import 'dart:async';

import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme_controller.dart';
import '../pages/chat/chat_page.dart';
import '../pages/image/image_page.dart';
import '../pages/settings/settings_page.dart';
import '../pages/video/video_page.dart';
import '../update/mobile_update_controller.dart';
import '../update/update_prompt_dialog.dart';
import 'app_section.dart';

/// Material 壳：Scaffold + 四入口 NavigationBar；IME 升起时随 viewInsets 收起底栏。
///
/// 根路由返回：先收键盘；否则「再按一次退出」（约 2s），确认后进最近任务，不清数据。
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
    this.updatePrefs,
    this.startupUpdateCheckDelay = const Duration(milliseconds: 800),
    this.exitConfirmWindow = const Duration(seconds: 2),
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
  final UpdatePrefs? updatePrefs;
  final Duration startupUpdateCheckDelay;
  final Duration exitConfirmWindow;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppSection _section = AppSection.chat;
  int _settingsTabIndex = 0;
  late final UpdatePrefs _updatePrefs;
  late final MobileUpdateController _updater;
  late final bool _ownsUpdater;
  bool _startupCheckStarted = false;
  bool _promptShowing = false;
  Timer? _startupCheckTimer;
  DateTime? _lastExitPromptAt;

  static const _sections = <AppSection>[
    AppSection.chat,
    AppSection.image,
    AppSection.video,
    AppSection.settings,
  ];

  @override
  void initState() {
    super.initState();
    _ownsUpdater = widget.updateController == null;
    _updater = widget.updateController ??
        MobileUpdateController(
          appLogRepository: widget.appLogRepository,
          updatePrefs: widget.updatePrefs,
        );
    // 优先复用 controller.prefs，避免壳层与控制器各持一份。
    _updatePrefs = _updater.prefs;
    _updater.addListener(_onUpdaterChanged);
    _updatePrefs.addListener(_onUpdaterChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduleStartupUpdateCheck();
    });
  }

  @override
  void dispose() {
    _startupCheckTimer?.cancel();
    _updater.removeListener(_onUpdaterChanged);
    _updatePrefs.removeListener(_onUpdaterChanged);
    if (_ownsUpdater) _updater.dispose();
    super.dispose();
  }

  void _onUpdaterChanged() {
    if (mounted) setState(() {});
  }

  void _onRootPopInvoked(bool didPop) {
    if (didPop) return;
    if (MediaQuery.viewInsetsOf(context).bottom > 0) {
      FocusManager.instance.primaryFocus?.unfocus();
      return;
    }

    final now = DateTime.now();
    final last = _lastExitPromptAt;
    final window = widget.exitConfirmWindow;
    if (last != null && now.difference(last) <= window) {
      _lastExitPromptAt = null;
      SystemNavigator.pop();
      return;
    }

    _lastExitPromptAt = now;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('再按一次退出'),
        duration: window,
      ),
    );
  }

  Widget _navIcon(AppSection section, {required bool selected}) {
    final icon = switch (section) {
      AppSection.chat => NavIcons.chat(selected: selected),
      AppSection.image => NavIcons.image(selected: selected),
      AppSection.video => NavIcons.video(selected: selected),
      AppSection.settings => NavIcons.settings(selected: selected),
    };
    if (section != AppSection.settings) return icon;
    return Badge(
      isLabelVisible: _updater.hasAvailableUpdate,
      smallSize: 8,
      child: icon,
    );
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
    setState(() => _section = next);
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
      await _updater.ensurePrefsLoaded();
      if (!_updater.autoCheckUpdate) return;

      final result = await _updater.checkForUpdate(silent: true);
      if (!mounted) return;
      if (result.status != UpdateCheckStatus.available) return;
      final version = result.latestVersion;
      if (version == null || version.trim().isEmpty) return;
      if (!await _updatePrefs.shouldPromptFor(version)) return;
      if (!mounted) return;
      await _showUpdatePrompt(result);
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

  Future<void> _showUpdatePrompt(UpdateCheckResult result) async {
    if (!mounted || _promptShowing) return;
    final version = result.latestVersion;
    if (version == null || version.trim().isEmpty) return;

    _promptShowing = true;
    final action = await showUpdatePromptDialog(
      context: context,
      result: result,
      isIos: _updater.isIos,
      iosMessage: MobileUpdateController.iosNonStoreMessage,
    );
    _promptShowing = false;
    if (!mounted) return;

    switch (action ?? UpdatePromptAction.later) {
      case UpdatePromptAction.skip:
        await _updater.skipUpdateVersion(version);
      case UpdatePromptAction.later:
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          const SnackBar(content: Text('可在 设置 → 关于 中安装')),
        );
      case UpdatePromptAction.install:
        if (_updater.isIos) return;
        final ok = await _updater.downloadAndInstall(result: result);
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        if (ok) {
          messenger.showSnackBar(
            const SnackBar(content: Text('已调起安装器，请按系统提示完成安装')),
          );
        } else {
          messenger.showSnackBar(
            SnackBar(content: Text(_updater.lastError ?? '下载或安装失败')),
          );
        }
    }
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _onRootPopInvoked(didPop),
      child: Scaffold(
        backgroundColor: tokens.canvas,
        // 键盘抬起只由内页 Scaffold 负责，避免双层 resize 叠跳。
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          bottom: false,
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
      ),
    );
  }
}
