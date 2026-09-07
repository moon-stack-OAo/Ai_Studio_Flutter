import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/theme_controller.dart';
import 'shell/app_shell.dart';
import 'update/mobile_update_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
  final videoClient = OpenAiCompatibleVideoClient();

  final dataBackup = DataBackupService(
    providers: providers,
    appearance: appearance,
    chatDefaults: chatDefaults,
    chatSessions: sessions,
    imageSessions: imageSessions,
    videoSessions: videoSessions,
    logs: appLogs,
  );

  final updateController = MobileUpdateController();

  runApp(
    AiStudioApp(
      themeController: themeController,
      providerRepository: providers,
      sessionRepository: sessions,
      imageSessionRepository: imageSessions,
      videoSessionRepository: videoSessions,
      chatDefaultsRepository: chatDefaults,
      appearanceRepository: appearance,
      appLogRepository: appLogs,
      dataBackupService: dataBackup,
      generation: generation,
      chatClient: chatClient,
      imageClient: imageClient,
      videoClient: videoClient,
      updateController: updateController,
    ),
  );
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
    required this.appearanceRepository,
    required this.appLogRepository,
    required this.dataBackupService,
    required this.generation,
    this.chatClient,
    this.imageClient,
    this.videoClient,
    this.updateController,
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
  final Duration startupUpdateCheckDelay;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        final scale = themeController.fontScale;
        final dens = themeController.density;
        return MaterialApp(
          title: 'AI Studio',
          debugShowCheckedModeBanner: false,
          themeMode: themeController.preference.themeMode,
          theme: buildMaterialLightTheme(fontScale: scale, density: dens),
          darkTheme: buildMaterialDarkTheme(fontScale: scale, density: dens),
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [
            Locale('zh', 'CN'),
            Locale('en'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: AppShell(
            themeController: themeController,
            providerRepository: providerRepository,
            sessionRepository: sessionRepository,
            imageSessionRepository: imageSessionRepository,
            videoSessionRepository: videoSessionRepository,
            chatDefaultsRepository: chatDefaultsRepository,
            appearanceRepository: appearanceRepository,
            appLogRepository: appLogRepository,
            dataBackupService: dataBackupService,
            generation: generation,
            chatClient: chatClient,
            imageClient: imageClient,
            videoClient: videoClient,
            updateController: updateController,
            startupUpdateCheckDelay: startupUpdateCheckDelay,
          ),
        );
      },
    );
  }
}
