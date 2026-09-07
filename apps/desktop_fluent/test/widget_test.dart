import 'package:core/core.dart';
import 'package:desktop_fluent/app/theme_controller.dart';
import 'package:desktop_fluent/main.dart';
import 'package:desktop_fluent/pages/chat/widgets/composer.dart';
import 'package:desktop_fluent/shell/app_section.dart';
import 'package:desktop_fluent/shell/update_banner.dart';
import 'package:desktop_fluent/widgets/session_list_pane.dart';
import 'package:desktop_fluent/pages/settings/settings_about_page.dart';
import 'package:desktop_fluent/pages/settings/settings_shell.dart';
import 'package:desktop_fluent/update/update_controller.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

Future<DataBackupService> makeBackup({
  required ProviderRepository providers,
  required ChatSessionRepository chatSessions,
  required ImageSessionRepository imageSessions,
  required VideoSessionRepository videoSessions,
  required ChatDefaultsRepository chatDefaults,
  AppearanceRepository? appearance,
  AppLogRepository? logs,
}) async {
  final appearanceRepo =
      appearance ?? AppearanceRepository(storage: MemoryAppearanceStorage());
  if (!appearanceRepo.isLoaded) await appearanceRepo.load();
  return DataBackupService(
    providers: providers,
    appearance: appearanceRepo,
    chatDefaults: chatDefaults,
    chatSessions: chatSessions,
    imageSessions: imageSessions,
    videoSessions: videoSessions,
    logs: logs,
  );
}

void main() {
  Future<AppLogRepository> makeLogs() async {
    final repo = AppLogRepository(storage: MemoryAppLogStorage());
    await repo.load();
    return repo;
  }

  Future<VideoSessionRepository> makeVideoSessions() async {
    final repo = VideoSessionRepository(
      storage: MemoryVideoSessionStorage(),
    );
    await repo.load();
    return repo;
  }

  testWidgets('section switch keeps pages via IndexedStack', (tester) async {
    final repo = ProviderRepository(
      storage: MemoryProviderStorage(),
      connectionTester: StubProviderConnectionTester(),
    );
    await repo.load();

    final sessions = ChatSessionRepository(
      storage: MemoryChatSessionStorage(),
    );
    await sessions.load();

    final chatDefaults = ChatDefaultsRepository(
      storage: MemoryChatDefaultsStorage(),
    );
    await chatDefaults.load();

    final imageSessions = ImageSessionRepository(
      storage: MemoryImageSessionStorage(),
    );
    await imageSessions.load();

    final videoSessions = await makeVideoSessions();
    final logs = await makeLogs();

    await tester.pumpWidget(
      AiStudioApp(
        themeController: ThemeController(),
        providerRepository: repo,
        sessionRepository: sessions,
        imageSessionRepository: imageSessions,
        videoSessionRepository: videoSessions,
        chatDefaultsRepository: chatDefaults,
        appLogRepository: logs,
        dataBackupService: await makeBackup(
          providers: repo,
          chatSessions: sessions,
          imageSessions: imageSessions,
          videoSessions: videoSessions,
          chatDefaults: chatDefaults,
          logs: logs,
        ),
        generation: GenerationRuntime(),
        startupUpdateCheckDelay: Duration.zero,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(IndexedStack), findsOneWidget);
    expect(find.text('尚未配置提供商'), findsOneWidget);

    // compact 侧栏只显示图标，title 作为 tooltip / semantics。
    await tester.tap(find.byTooltip('生图'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('尚未配置生图模型'), findsOneWidget);
    expect(find.byType(IndexedStack), findsOneWidget);

    await tester.tap(find.byTooltip('对话'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('尚未配置提供商'), findsOneWidget);
  });

  testWidgets('shell shows chat empty state', (tester) async {
    final repo = ProviderRepository(
      storage: MemoryProviderStorage(),
      connectionTester: StubProviderConnectionTester(),
    );
    await repo.load();

    final sessions = ChatSessionRepository(
      storage: MemoryChatSessionStorage(),
    );
    await sessions.load();

    final chatDefaults = ChatDefaultsRepository(
      storage: MemoryChatDefaultsStorage(),
    );
    await chatDefaults.load();

    final imageSessions = ImageSessionRepository(
      storage: MemoryImageSessionStorage(),
    );
    await imageSessions.load();

    final videoSessions = await makeVideoSessions();
    final logs = await makeLogs();

    await tester.pumpWidget(
      AiStudioApp(
        themeController: ThemeController(),
        providerRepository: repo,
        sessionRepository: sessions,
        imageSessionRepository: imageSessions,
        videoSessionRepository: videoSessions,
        chatDefaultsRepository: chatDefaults,
        appLogRepository: logs,
        dataBackupService: await makeBackup(
          providers: repo,
          chatSessions: sessions,
          imageSessions: imageSessions,
          videoSessions: videoSessions,
          chatDefaults: chatDefaults,
          logs: logs,
        ),
        generation: GenerationRuntime(),
        startupUpdateCheckDelay: Duration.zero,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('尚未配置提供商'), findsWidgets);
    expect(find.text('去设置'), findsOneWidget);
  });

  testWidgets('configured provider shows session list and composer',
      (tester) async {
    final repo = ProviderRepository(
      storage: MemoryProviderStorage(
        ProviderStoreSnapshot(
          providers: [
            ProviderConfig(
              id: 'p1',
              name: 'Local',
              type: ProviderType.openaiCompatible,
              baseUrl: 'https://api.example.com/v1',
              apiKey: 'sk-test-key',
              chatModel: 'gpt-test',
              enabled: true,
            ),
          ],
          activeProviderId: 'p1',
        ),
      ),
      connectionTester: StubProviderConnectionTester(),
    );
    await repo.load();

    final sessions = ChatSessionRepository(
      storage: MemoryChatSessionStorage(),
    );
    await sessions.load();

    final chatDefaults = ChatDefaultsRepository(
      storage: MemoryChatDefaultsStorage(),
    );
    await chatDefaults.load();

    final imageSessions = ImageSessionRepository(
      storage: MemoryImageSessionStorage(),
    );
    await imageSessions.load();

    final videoSessions = await makeVideoSessions();
    final logs = await makeLogs();

    await tester.pumpWidget(
      AiStudioApp(
        themeController: ThemeController(),
        providerRepository: repo,
        sessionRepository: sessions,
        imageSessionRepository: imageSessions,
        videoSessionRepository: videoSessions,
        chatDefaultsRepository: chatDefaults,
        appLogRepository: logs,
        dataBackupService: await makeBackup(
          providers: repo,
          chatSessions: sessions,
          imageSessions: imageSessions,
          videoSessions: videoSessions,
          chatDefaults: chatDefaults,
          logs: logs,
        ),
        generation: GenerationRuntime(),
        startupUpdateCheckDelay: Duration.zero,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('尚未配置提供商'), findsNothing);
    expect(find.text('去设置'), findsNothing);
    expect(find.text('会话'), findsOneWidget);
    expect(find.text('新对话'), findsWidgets);
    expect(find.text('还没有消息'), findsOneWidget);
    expect(find.text('选择左侧会话，或在下方输入第一条消息开始对话。'), findsOneWidget);
    expect(find.text('发送'), findsOneWidget);
    expect(find.textContaining('Local · gpt-test'), findsOneWidget);
    expect(find.text('会话参数'), findsOneWidget);
  });

  testWidgets('session list pane empty shows create CTA', (tester) async {
    var created = false;
    await tester.pumpWidget(
      FluentApp(
        home: ScaffoldPage(
          content: SessionListPane(
            sessions: const [],
            selectedId: '',
            onSelect: (_) {},
            onCreate: () => created = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂无会话'), findsOneWidget);
    expect(find.text('新建会话'), findsOneWidget);
    await tester.tap(find.text('新建会话'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(created, isTrue);
  });

  testWidgets('about page shows version and persists closeBehavior',
      (tester) async {
    final appearance = AppearanceRepository(
      storage: MemoryAppearanceStorage(),
    );
    await appearance.load();

    final providers = ProviderRepository(
      storage: MemoryProviderStorage(),
      connectionTester: StubProviderConnectionTester(),
    );
    await providers.load();
    final chatSessions =
        ChatSessionRepository(storage: MemoryChatSessionStorage());
    await chatSessions.load();
    final imageSessions =
        ImageSessionRepository(storage: MemoryImageSessionStorage());
    await imageSessions.load();
    final videoSessions = await makeVideoSessions();
    final chatDefaults = ChatDefaultsRepository(
      storage: MemoryChatDefaultsStorage(),
    );
    await chatDefaults.load();

    final fakeInfo = PackageInfo(
      appName: 'AI Studio',
      packageName: 'desktop_fluent',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    final updateController = UpdateController(
      client: UpdateClient(manifestUrl: kDesktopUpdateManifestUrl),
      currentVersion: '1.0.0',
    );

    await tester.pumpWidget(
      FluentApp(
        home: SettingsAboutPage(
          appearanceRepository: appearance,
          dataBackupService: await makeBackup(
            providers: providers,
            chatSessions: chatSessions,
            imageSessions: imageSessions,
            videoSessions: videoSessions,
            chatDefaults: chatDefaults,
            appearance: appearance,
          ),
          updateController: updateController,
          packageInfo: fakeInfo,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('关于与更新'), findsOneWidget);
    expect(find.textContaining('1.0.0+1'), findsOneWidget);
    expect(find.text('每次询问'), findsOneWidget);
    expect(find.text('直接退出'), findsOneWidget);
    expect(find.text('最小化到托盘'), findsOneWidget);
    expect(appearance.settings.closeBehavior, 'ask');

    await tester.tap(find.text('直接退出'));
    await tester.pumpAndSettle();
    expect(appearance.settings.closeBehavior, 'quit');

    expect(find.text('检查更新'), findsOneWidget);
    expect(find.textContaining('已生效'), findsOneWidget);
    expect(find.textContaining('本仓 Releases'), findsOneWidget);
    expect(find.text('导出设置'), findsOneWidget);
    expect(find.text('导入设置'), findsOneWidget);
    expect(find.text('清除本地数据'), findsOneWidget);
    expect(find.textContaining('危险操作需确认'), findsNothing);
    expect(find.textContaining('默认导出不含 API Key'), findsOneWidget);
  });

  testWidgets('about clear data shows confirm dialog', (tester) async {
    final appearance = AppearanceRepository(
      storage: MemoryAppearanceStorage(),
    );
    await appearance.load();
    final providers = ProviderRepository(
      storage: MemoryProviderStorage(),
      connectionTester: StubProviderConnectionTester(),
    );
    await providers.load();
    final chatSessions =
        ChatSessionRepository(storage: MemoryChatSessionStorage());
    await chatSessions.load();
    final imageSessions =
        ImageSessionRepository(storage: MemoryImageSessionStorage());
    await imageSessions.load();
    final videoSessions = await makeVideoSessions();
    final chatDefaults = ChatDefaultsRepository(
      storage: MemoryChatDefaultsStorage(),
    );
    await chatDefaults.load();

    await tester.pumpWidget(
      FluentApp(
        home: SettingsAboutPage(
          appearanceRepository: appearance,
          dataBackupService: await makeBackup(
            providers: providers,
            chatSessions: chatSessions,
            imageSessions: imageSessions,
            videoSessions: videoSessions,
            chatDefaults: chatDefaults,
            appearance: appearance,
          ),
          packageInfo: PackageInfo(
            appName: 'AI Studio',
            packageName: 'desktop_fluent',
            version: '1.0.0',
            buildNumber: '1',
            buildSignature: '',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final clearBtn = find.text('清除本地数据');
    await tester.ensureVisible(clearBtn);
    await tester.pumpAndSettle();
    await tester.tap(clearBtn);
    await tester.pumpAndSettle();
    expect(find.text('仅会话（对话 / 生图 / 生视频）'), findsOneWidget);
    expect(find.text('仅媒体缓存'), findsOneWidget);
    expect(find.text('全部（含设置与密钥）'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });

  testWidgets('session list row exposes semantics label', (tester) async {
    await tester.pumpWidget(
      FluentApp(
        home: ScaffoldPage(
          content: SessionListPane(
            sessions: const [
              SessionListItem(id: 's1', title: '测试会话', subtitle: '今天'),
            ],
            selectedId: 's1',
            onSelect: (_) {},
            onCreate: () {},
            onDelete: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byTooltip('新建会话'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'测试会话')),
      findsWidgets,
    );
  });

  testWidgets('composer send/stop expose tooltips and labels', (tester) async {
    await tester.pumpWidget(
      FluentApp(
        home: ScaffoldPage(
          content: Composer(
            enabled: true,
            streaming: false,
            onSend: (_) {},
            onStop: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('发送'), findsOneWidget);
    expect(find.byTooltip('发送（Enter）'), findsOneWidget);

    await tester.pumpWidget(
      FluentApp(
        home: ScaffoldPage(
          content: Composer(
            enabled: true,
            streaming: true,
            onSend: (_) {},
            onStop: () {},
          ),
        ),
      ),
    );
    // 流式态有脉冲动画，勿 pumpAndSettle
    await tester.pump();

    expect(find.text('停止'), findsOneWidget);
    expect(find.byTooltip('停止生成'), findsOneWidget);
    expect(find.bySemanticsLabel('消息输入'), findsWidgets);
  });

  testWidgets('settings category tiles expose semantics labels', (tester) async {
    final appearance = AppearanceRepository(storage: MemoryAppearanceStorage());
    await appearance.load();
    final providers = ProviderRepository(
      storage: MemoryProviderStorage(),
      connectionTester: StubProviderConnectionTester(),
    );
    await providers.load();
    final chatDefaults =
        ChatDefaultsRepository(storage: MemoryChatDefaultsStorage());
    await chatDefaults.load();
    final logs = await makeLogs();
    final chatSessions =
        ChatSessionRepository(storage: MemoryChatSessionStorage());
    await chatSessions.load();
    final imageSessions =
        ImageSessionRepository(storage: MemoryImageSessionStorage());
    await imageSessions.load();
    final videoSessions = await makeVideoSessions();
    final backup = await makeBackup(
      providers: providers,
      chatSessions: chatSessions,
      imageSessions: imageSessions,
      videoSessions: videoSessions,
      chatDefaults: chatDefaults,
      appearance: appearance,
      logs: logs,
    );
    final theme = ThemeController(repository: appearance);
    theme.loadFrom(appearance.settings);

    await tester.pumpWidget(
      FluentApp(
        home: ScaffoldPage(
          content: SettingsShell(
            category: SettingsCategory.providers,
            onCategoryChanged: (_) {},
            themeController: theme,
            appearanceRepository: appearance,
            providerRepository: providers,
            chatDefaultsRepository: chatDefaults,
            appLogRepository: logs,
            dataBackupService: backup,
            generation: GenerationRuntime(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.bySemanticsLabel(RegExp(r'提供商')), findsWidgets);
    expect(find.bySemanticsLabel(RegExp(r'外观')), findsWidgets);
  });

  testWidgets('update banner is a live region', (tester) async {
    await tester.pumpWidget(
      FluentApp(
        home: ScaffoldPage(
          content: UpdateBanner(
            version: '1.2.3',
            onGoUpdate: () {},
            onLater: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.bySemanticsLabel(RegExp(r'发现新版本 1\.2\.3')),
      findsWidgets,
    );
  });
}
