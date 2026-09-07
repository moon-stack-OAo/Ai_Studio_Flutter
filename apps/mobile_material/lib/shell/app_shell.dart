import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';

import '../app/theme_controller.dart';
import '../pages/chat/chat_page.dart';
import '../pages/image/image_page.dart';
import '../pages/settings/settings_page.dart';
import '../pages/video/video_page.dart';
import 'app_section.dart';

/// Material 壳：Scaffold + 四入口 NavigationBar；IME 可见时隐藏底栏。
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

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppSection _section = AppSection.chat;
  int _settingsTabIndex = 0;
  double _paneOpacity = 1;

  static const _sections = <AppSection>[
    AppSection.chat,
    AppSection.image,
    AppSection.video,
    AppSection.settings,
  ];

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

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    final imeVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final selectedIndex = AppSection.values.indexOf(_section);

    return Scaffold(
      backgroundColor: tokens.canvas,
      body: SafeArea(
        bottom: false,
        // IndexedStack 保各 tab 状态；短 opacity 作分区切换动效。
        child: AnimatedOpacity(
          opacity: _paneOpacity,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
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
                  )
                else
                  const SizedBox.shrink(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: imeVisible
          ? null
          : NavigationBar(
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
    );
  }
}
