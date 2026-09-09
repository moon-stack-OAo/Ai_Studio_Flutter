import 'dart:io' show Platform;

import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'app/theme_controller.dart';
import 'shell/app_shell.dart';
import 'shell/brand_intro_gate.dart';
import 'shell/window_bootstrap.dart';
import 'shell/window_close_coordinator.dart';
import 'update/update_controller.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  await bootstrapDesktopWindow();

  final providers = ProviderRepository(storage: SecureProviderStorage());
  await providers.load();

  final sessions = ChatSessionRepository(storage: PrefsChatSessionStorage());
  await sessions.load();

  final imageSessions = ImageSessionRepository(
    storage: PrefsImageSessionStorage(),
    assetStore: FileImageAssetStore(),
  );
  await imageSessions.load();

  final videoSessions = VideoSessionRepository(
    storage: PrefsVideoSessionStorage(),
    assetStore: FileVideoAssetStore(),
  );
  await videoSessions.load();

  final chatDefaults =
      ChatDefaultsRepository(storage: PrefsChatDefaultsStorage());
  await chatDefaults.load();

  final appearance =
      AppearanceRepository(storage: PrefsAppearanceStorage());
  await appearance.load();

  final appLogs = AppLogRepository(storage: PrefsAppLogStorage());
  await appLogs.load();
  await appLogs.append(
    level: AppLogLevel.info,
    source: AppLogSources.system,
    message: '应用启动',
  );

  final themeController = ThemeController(repository: appearance);
  themeController.loadFrom(appearance.settings);

  final generation = GenerationRuntime();
  final chatClient = OpenAiCompatibleChatClient();
  final imageClient = OpenAiCompatibleImageClient();
  final videoClient = OpenAiCompatibleVideoClient(logs: appLogs);

  final navigatorKey = GlobalKey<NavigatorState>();
  final closeCoordinator = WindowCloseCoordinator(
    appearanceRepository: appearance,
    navigatorKey: navigatorKey,
    onBeforeQuit: () => generation.abort(),
  );

  final updateController = UpdateController(
    client: UpdateClient(manifestUrl: kDesktopUpdateManifestUrl),
    appLogRepository: appLogs,
    onQuitAfterInstall: closeCoordinator.quitApp,
  );

  final dataBackup = DataBackupService(
    providers: providers,
    appearance: appearance,
    chatDefaults: chatDefaults,
    chatSessions: sessions,
    imageSessions: imageSessions,
    videoSessions: videoSessions,
    logs: appLogs,
  );

  // P3：正式构建保持语义树开启；Windows debug 整树关闭，规避已知 AXTree 刷错
  //（flutter#182444，Tooltip/ListView 语义嫁接；修复尚未进 stable）。
  // 局部易炸控件（如模型 tag）仍各自 ExcludeSemantics。
  Widget app = AiStudioApp(
    themeController: themeController,
    providerRepository: providers,
    sessionRepository: sessions,
    imageSessionRepository: imageSessions,
    videoSessionRepository: videoSessions,
    chatDefaultsRepository: chatDefaults,
    appLogRepository: appLogs,
    dataBackupService: dataBackup,
    generation: generation,
    chatClient: chatClient,
    imageClient: imageClient,
    videoClient: videoClient,
    updateController: updateController,
    navigatorKey: navigatorKey,
    closeCoordinator: closeCoordinator,
  );
  if (kDebugMode && Platform.isWindows) {
    app = ExcludeSemantics(child: app);
  }
  runApp(app);
  FlutterNativeSplash.remove();
}

class AiStudioApp extends StatelessWidget {
  const AiStudioApp({
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
    this.navigatorKey,
    this.closeCoordinator,
    this.startupUpdateCheckDelay = const Duration(milliseconds: 1800),
    this.showBrandIntro = true,
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
  final GlobalKey<NavigatorState>? navigatorKey;
  final WindowCloseCoordinator? closeCoordinator;
  final Duration startupUpdateCheckDelay;
  final bool showBrandIntro;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        final scale = themeController.fontScale;
        final dens = themeController.density;
        final shell = AppShell(
          themeController: themeController,
          providerRepository: providerRepository,
          sessionRepository: sessionRepository,
          imageSessionRepository: imageSessionRepository,
          videoSessionRepository: videoSessionRepository,
          chatDefaultsRepository: chatDefaultsRepository,
          appLogRepository: appLogRepository,
          dataBackupService: dataBackupService,
          generation: generation,
          chatClient: chatClient,
          imageClient: imageClient,
          videoClient: videoClient,
          updateController: updateController,
          closeCoordinator: closeCoordinator,
          startupUpdateCheckDelay: startupUpdateCheckDelay,
        );
        return FluentApp(
          title: 'AI Studio',
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          themeMode: themeController.preference.themeMode,
          theme: buildFluentLightTheme(fontScale: scale, density: dens),
          darkTheme: buildFluentDarkTheme(fontScale: scale, density: dens),
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [
            Locale('zh', 'CN'),
            Locale('en'),
          ],
          home: showBrandIntro ? BrandIntroGate(child: shell) : shell,
        );
      },
    );
  }
}
