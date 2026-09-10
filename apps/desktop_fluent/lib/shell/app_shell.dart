import 'dart:async';

import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../app/theme_controller.dart';
import '../pages/chat_page.dart';
import '../pages/image/image_page.dart';
import '../pages/settings/settings_shell.dart';
import '../pages/video/video_page.dart';
import '../update/update_controller.dart';
import '../update/update_prompt_dialog.dart';
import 'app_section.dart';
import 'fluent_app_title_bar.dart';
import 'title_bar_theme_button.dart';
import 'window_bootstrap.dart';
import 'window_close_coordinator.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.themeController,
    required this.providerRepository,
    required this.sessionRepository,
    required this.imageSessionRepository,
    required this.videoSessionRepository,
    required this.chatDefaultsRepository,
    required this.appLogRepository,
    required this.dataBackupService,
    required this.generation,
    this.chatClient,
    this.imageClient,
    this.videoClient,
    this.updateController,
    this.closeCoordinator,
    this.updatePrefs,
    @Deprecated('Use updatePrefs') this.updateBannerPrefs,
    this.startupUpdateCheckDelay = const Duration(milliseconds: 1800),
  });

  final ThemeController themeController;
  final ProviderRepository providerRepository;
  final ChatSessionRepository sessionRepository;
  final ImageSessionRepository imageSessionRepository;
  final VideoSessionRepository videoSessionRepository;
  final ChatDefaultsRepository chatDefaultsRepository;
  final AppLogRepository appLogRepository;
  final DataBackupService dataBackupService;
  final GenerationRuntime generation;
  final OpenAiCompatibleChatClient? chatClient;
  final OpenAiCompatibleImageClient? imageClient;
  final OpenAiCompatibleVideoClient? videoClient;
  final UpdateController? updateController;
  final WindowCloseCoordinator? closeCoordinator;
  final UpdatePrefs? updatePrefs;

  /// 兼容旧测试参数名；优先 [updatePrefs]。
  @Deprecated('Use updatePrefs')
  final UpdatePrefs? updateBannerPrefs;
  final Duration startupUpdateCheckDelay;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppSection _section = AppSection.chat;
  SettingsCategory _settingsCategory = SettingsCategory.providers;
  late final AppearanceRepository _fallbackAppearance =
      AppearanceRepository(storage: MemoryAppearanceStorage());
  late final List<Widget> _sectionPages;
  late final UpdatePrefs _updatePrefs;
  bool _startupCheckStarted = false;
  bool _updateDialogVisible = false;
  Timer? _startupCheckTimer;

  AppearanceRepository get _appearanceRepository =>
      widget.themeController.appearanceRepository ?? _fallbackAppearance;

  @override
  void initState() {
    super.initState();
    final injected = widget.updatePrefs ?? widget.updateBannerPrefs;
    final controllerPrefs = widget.updateController?.prefs;
    if (injected != null) {
      _updatePrefs = injected;
    } else if (controllerPrefs != null) {
      _updatePrefs = controllerPrefs;
    } else {
      _updatePrefs = UpdatePrefs();
    }
    widget.updateController?.addListener(_onUpdaterChanged);
    _updatePrefs.addListener(_onUpdaterChanged);
    _sectionPages = [
      ChatPage(
        providerRepository: widget.providerRepository,
        sessionRepository: widget.sessionRepository,
        chatDefaultsRepository: widget.chatDefaultsRepository,
        appLogRepository: widget.appLogRepository,
        generation: widget.generation,
        chatClient: widget.chatClient,
        onOpenProviders: _openProviders,
      ),
      ImagePage(
        providerRepository: widget.providerRepository,
        sessionRepository: widget.imageSessionRepository,
        chatDefaultsRepository: widget.chatDefaultsRepository,
        appLogRepository: widget.appLogRepository,
        generation: widget.generation,
        chatClient: widget.chatClient,
        imageClient: widget.imageClient,
        onOpenProviders: _openProviders,
      ),
      VideoPage(
        providerRepository: widget.providerRepository,
        sessionRepository: widget.videoSessionRepository,
        chatDefaultsRepository: widget.chatDefaultsRepository,
        appLogRepository: widget.appLogRepository,
        generation: widget.generation,
        chatClient: widget.chatClient,
        videoClient: widget.videoClient,
        onOpenProviders: _openProviders,
      ),
      // SettingsShell 依赖可变 category，单独在 build 中组装。
    ];
    final coordinator = widget.closeCoordinator;
    if (coordinator != null && supportsCustomTitleBar) {
      coordinator.onOpenSettings = _openSettingsFromTray;
      coordinator.onCheckUpdate = _checkUpdateFromTray;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        coordinator.attach();
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduleStartupUpdateCheck();
    });
  }

  @override
  void dispose() {
    _startupCheckTimer?.cancel();
    widget.updateController?.removeListener(_onUpdaterChanged);
    _updatePrefs.removeListener(_onUpdaterChanged);
    final coordinator = widget.closeCoordinator;
    if (coordinator != null && supportsCustomTitleBar) {
      unawaited(coordinator.detach());
    }
    super.dispose();
  }

  void _onUpdaterChanged() {
    if (mounted) setState(() {});
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

    final updater = widget.updateController;
    if (updater == null || !updater.isConfigured) return;
    if (updater.isChecking || updater.isDownloading) return;

    try {
      await _updatePrefs.ensureLoaded();
      if (!_updatePrefs.autoCheckUpdate) return;

      final result = await updater.checkForUpdate(silent: true);
      if (!mounted) return;
      if (result.status != UpdateCheckStatus.available) return;
      final version = result.latestVersion;
      if (version == null || version.trim().isEmpty) return;
      if (!await _updatePrefs.shouldPromptFor(version)) return;
      if (!mounted) return;
      await _presentUpdatePrompt(result);
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

  void _openSettingsFromTray() {
    if (!mounted) return;
    setState(() {
      _section = AppSection.settings;
      _settingsCategory = SettingsCategory.about;
    });
  }

  void _checkUpdateFromTray() {
    if (!mounted) return;
    unawaited(_runCheckUpdateFromTray());
  }

  Future<void> _runCheckUpdateFromTray() async {
    final updater = widget.updateController;
    if (updater == null) {
      if (!mounted) return;
      _showInfoBar('更新服务未初始化', InfoBarSeverity.warning);
      return;
    }
    if (!updater.isConfigured) {
      if (!mounted) return;
      _showInfoBar('未配置更新源', InfoBarSeverity.warning);
      return;
    }
    if (updater.isChecking || updater.isDownloading) return;

    final result = await updater.checkForUpdate(silent: false);
    if (!mounted) return;

    if (result.status == UpdateCheckStatus.available) {
      await _presentUpdatePrompt(result);
      return;
    }

    final (String title, InfoBarSeverity severity) = switch (result.status) {
      UpdateCheckStatus.upToDate => (
          '已是最新版本（${result.latestVersion ?? result.currentVersion}）',
          InfoBarSeverity.success,
        ),
      UpdateCheckStatus.available => (
          '发现新版本 ${result.latestVersion}',
          InfoBarSeverity.info,
        ),
      UpdateCheckStatus.notConfigured => (
          '未配置更新源',
          InfoBarSeverity.warning,
        ),
      UpdateCheckStatus.noPlatformAsset => (
          result.errorMessage ?? '清单中无当前平台的安装包',
          InfoBarSeverity.warning,
        ),
      UpdateCheckStatus.failed => (
          result.errorMessage ?? '检查更新失败',
          InfoBarSeverity.error,
        ),
    };

    _showInfoBar(title, severity);
  }

  Future<void> _presentUpdatePrompt(UpdateCheckResult result) async {
    if (!mounted || _updateDialogVisible) return;
    final updater = widget.updateController;
    if (updater == null) return;

    _updateDialogVisible = true;
    try {
      final action = await showUpdatePromptDialog(
        context: context,
        result: result,
      );
      if (!mounted) return;

      switch (action ?? UpdatePromptAction.later) {
        case UpdatePromptAction.skip:
          await updater.skipUpdateVersion(result.latestVersion);
        case UpdatePromptAction.later:
          _showInfoBar(
            '可在 设置 → 关于与更新 中安装',
            InfoBarSeverity.info,
          );
        case UpdatePromptAction.install:
          _showInfoBar('正在下载更新…', InfoBarSeverity.info);
          final ok = await updater.downloadAndInstall(result: result);
          if (!mounted) return;
          if (!ok) {
            _showInfoBar(
              updater.lastError ?? '下载或安装失败',
              InfoBarSeverity.error,
            );
          }
      }
    } finally {
      _updateDialogVisible = false;
    }
  }

  void _showInfoBar(String message, InfoBarSeverity severity) {
    displayInfoBar(
      context,
      builder: (context, close) {
        return InfoBar(
          title: Text(message),
          severity: severity,
          onClose: close,
        );
      },
    );
  }

  int get _selectedIndex => switch (_section) {
        AppSection.chat => 0,
        AppSection.image => 1,
        AppSection.video => 2,
        AppSection.settings => 3,
      };

  void _openProviders() {
    setState(() {
      _section = AppSection.settings;
      _settingsCategory = SettingsCategory.providers;
    });
  }

  void _onPaneChanged(int index) {
    final next = switch (index) {
      0 => AppSection.chat,
      1 => AppSection.image,
      2 => AppSection.video,
      _ => AppSection.settings,
    };
    if (next == _section) return;
    setState(() => _section = next);
  }

  bool get _showUpdateBadge {
    final updater = widget.updateController;
    if (updater != null) return updater.hasAvailableUpdate;
    return _updatePrefs.hasAvailableUpdate;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    final coordinator = widget.closeCoordinator;
    final showBadge = _showUpdateBadge;

    return Column(
      children: [
        FluentAppTitleBar(
          title: 'AI Studio · ${_section.label}',
          onClose: coordinator?.requestClose,
          endActions: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 4),
              child: TitleBarThemeButton(
                controller: widget.themeController,
              ),
            ),
          ],
        ),
        Expanded(
          child: FluentTheme(
            // 侧栏同级切换：短淡入，避免 Entrance 位移「飘」感。
            data: FluentTheme.of(context).copyWith(
              fastAnimationDuration: FluentMotion.sectionSwitch,
              animationCurve: FluentMotion.standard,
            ),
            child: NavigationView(
              // fluent_ui 默认 body 用 ValueKey(selected) 换页，切走即 dispose；
              // paneBodyBuilder + IndexedStack 对齐移动端/现网：切页保活、不中断生成。
              // 关闭 NavigationView 自带换页动画；IndexedStack 直切保活，无淡入以免闪烁。
              transitionBuilder: (child, animation) => child,
              paneBodyBuilder: (item, body) {
                return IndexedStack(
                  key: const ValueKey('desktop_section_host'),
                  index: _selectedIndex,
                  sizing: StackFit.expand,
                  children: [
                    ..._sectionPages,
                    SettingsShell(
                      category: _settingsCategory,
                      onCategoryChanged: (value) {
                        setState(() => _settingsCategory = value);
                      },
                      themeController: widget.themeController,
                      appearanceRepository: _appearanceRepository,
                      providerRepository: widget.providerRepository,
                      chatDefaultsRepository: widget.chatDefaultsRepository,
                      appLogRepository: widget.appLogRepository,
                      dataBackupService: widget.dataBackupService,
                      generation: widget.generation,
                      updateController: widget.updateController,
                    ),
                  ],
                );
              },
              pane: NavigationPane(
                selected: _selectedIndex,
                onChanged: _onPaneChanged,
                displayMode: PaneDisplayMode.compact,
                // 对齐原型：常驻 ~56px 图标窄栏，禁止展开成宽侧栏
                toggleable: false,
                toggleButton: null,
                size: NavigationPaneSize(compactWidth: tokens.navWidth),
                items: [
                  PaneItem(
                    icon: NavIcons.chat(selected: _section == AppSection.chat),
                    title: const Text('对话'),
                    body: const SizedBox.shrink(),
                  ),
                  PaneItem(
                    icon: NavIcons.image(selected: _section == AppSection.image),
                    title: const Text('生图'),
                    body: const SizedBox.shrink(),
                  ),
                  PaneItem(
                    icon: NavIcons.video(selected: _section == AppSection.video),
                    title: const Text('生视频'),
                    body: const SizedBox.shrink(),
                  ),
                ],
                footerItems: [
                  PaneItem(
                    icon: NavIcons.settings(
                      selected: _section == AppSection.settings,
                    ),
                    title: const Text('设置'),
                    infoBadge: showBadge
                        ? const InfoBadge(source: Text('NEW'))
                        : null,
                    body: const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
