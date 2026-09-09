import 'dart:async';

import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/theme_controller.dart';
import 'shell/app_shell.dart';
import 'shell/brand_intro_gate.dart';
import 'update/mobile_update_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 仅预加载外观，尽快画出 BrandIntro（正确亮/暗）
  final appearance =
      AppearanceRepository(storage: PrefsAppearanceStorage());
  await appearance.load();

  final themeController = ThemeController(repository: appearance);
  themeController.loadFrom(appearance.settings);

  final providers = ProviderRepository(storage: SecureProviderStorage());
  final sessions = ChatSessionRepository(storage: PrefsChatSessionStorage());
  final imageSessions = ImageSessionRepository(
    storage: PrefsImageSessionStorage(),
    assetStore: FileImageAssetStore(),
  );
  final videoSessions = VideoSessionRepository(
    storage: PrefsVideoSessionStorage(),
    assetStore: FileVideoAssetStore(),
  );
  final chatDefaults =
      ChatDefaultsRepository(storage: PrefsChatDefaultsStorage());
  final appLogs = AppLogRepository(storage: PrefsAppLogStorage());

  final generation = GenerationRuntime();
  final chatClient = OpenAiCompatibleChatClient();
  final imageClient = OpenAiCompatibleImageClient();
  final videoClient = OpenAiCompatibleVideoClient(logs: appLogs);

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
      bootstrap: () async {
        await Future.wait<void>([
          providers.load(),
          sessions.load(),
          imageSessions.load(),
          videoSessions.load(),
          chatDefaults.load(),
          appLogs.load(),
        ]);
        await appLogs.append(
          level: AppLogLevel.info,
          source: AppLogSources.system,
          message: '应用启动',
        );
      },
    ),
  );
}

class AiStudioApp extends StatefulWidget {
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
    this.showBrandIntro = true,
    this.bootstrap,
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
  final bool showBrandIntro;

  /// 非空时在首帧后后台执行；完成前不挂载 [AppShell]，品牌覆层也不拆除。
  final Future<void> Function()? bootstrap;

  @override
  State<AiStudioApp> createState() => _AiStudioAppState();
}

class _AiStudioAppState extends State<AiStudioApp> {
  late final ValueNotifier<bool> _shellReady;

  @override
  void initState() {
    super.initState();
    final bootstrap = widget.bootstrap;
    if (bootstrap == null) {
      _shellReady = ValueNotifier<bool>(true);
    } else {
      _shellReady = ValueNotifier<bool>(false);
      unawaited(_runBootstrap(bootstrap));
    }
  }

  Future<void> _runBootstrap(Future<void> Function() bootstrap) async {
    try {
      await bootstrap();
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'main',
          context: ErrorDescription('during app bootstrap'),
        ),
      );
    }
    if (!mounted) return;
    _shellReady.value = true;
  }

  @override
  void dispose() {
    _shellReady.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.themeController,
      builder: (context, _) {
        final scale = widget.themeController.fontScale;
        final dens = widget.themeController.density;
        return MaterialApp(
          title: 'AI Studio',
          debugShowCheckedModeBanner: false,
          themeMode: widget.themeController.preference.themeMode,
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
          home: ListenableBuilder(
            listenable: _shellReady,
            builder: (context, _) {
              final ready = _shellReady.value;
              final shell = ready
                  ? AppShell(
                      themeController: widget.themeController,
                      providerRepository: widget.providerRepository,
                      sessionRepository: widget.sessionRepository,
                      imageSessionRepository: widget.imageSessionRepository,
                      videoSessionRepository: widget.videoSessionRepository,
                      chatDefaultsRepository: widget.chatDefaultsRepository,
                      appearanceRepository: widget.appearanceRepository,
                      appLogRepository: widget.appLogRepository,
                      dataBackupService: widget.dataBackupService,
                      generation: widget.generation,
                      chatClient: widget.chatClient,
                      imageClient: widget.imageClient,
                      videoClient: widget.videoClient,
                      updateController: widget.updateController,
                      startupUpdateCheckDelay: widget.startupUpdateCheckDelay,
                    )
                  : const SizedBox.shrink();

              if (!widget.showBrandIntro) {
                if (!ready) {
                  return const ColoredBox(
                    color: Color(0xFFfaf9f5),
                    child: SizedBox.expand(),
                  );
                }
                return shell;
              }

              return BrandIntroGate(
                ready: _shellReady,
                child: shell,
              );
            },
          ),
        );
      },
    );
  }
}
