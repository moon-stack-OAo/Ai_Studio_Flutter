import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_material/app/theme_controller.dart';
import 'package:mobile_material/main.dart';
import 'package:mobile_material/pages/chat/session_list_page.dart';
import 'package:mobile_material/pages/image/widgets/image_composer.dart';
import 'package:mobile_material/pages/settings/settings_providers_tab.dart';
import 'package:mobile_material/shell/brand_intro_gate.dart';
import 'package:mobile_material/shell/update_banner.dart';
import 'package:design_material/design_material.dart';
import 'package:package_info_plus/package_info_plus.dart';

void _noop() {}
Future<void> _pumpApp(
  WidgetTester tester, {
  ProviderRepository? providers,
  ChatSessionRepository? sessions,
  ImageSessionRepository? imageSessions,
  VideoSessionRepository? videoSessions,
}) async {
  final providerRepo = providers ??
      ProviderRepository(
        storage: MemoryProviderStorage(),
        connectionTester: StubProviderConnectionTester(),
      );
  await providerRepo.load();

  final sessionRepo =
      sessions ?? ChatSessionRepository(storage: MemoryChatSessionStorage());
  await sessionRepo.load();

  final imageRepo = imageSessions ??
      ImageSessionRepository(storage: MemoryImageSessionStorage());
  await imageRepo.load();

  final videoRepo = videoSessions ??
      VideoSessionRepository(storage: MemoryVideoSessionStorage());
  await videoRepo.load();

  final chatDefaults = ChatDefaultsRepository(
    storage: MemoryChatDefaultsStorage(),
  );
  await chatDefaults.load();

  final appearance = AppearanceRepository(
    storage: MemoryAppearanceStorage(),
  );
  await appearance.load();

  final appLogs = AppLogRepository(storage: MemoryAppLogStorage());
  await appLogs.load();
  await appLogs.append(
    level: AppLogLevel.info,
    source: AppLogSources.system,
    message: '应用启动',
  );

  final themeController = ThemeController(repository: appearance);
  themeController.loadFrom(appearance.settings);

  final dataBackup = DataBackupService(
    providers: providerRepo,
    appearance: appearance,
    chatDefaults: chatDefaults,
    chatSessions: sessionRepo,
    imageSessions: imageRepo,
    videoSessions: videoRepo,
    logs: appLogs,
  );

  await tester.pumpWidget(
    AiStudioApp(
      themeController: themeController,
      providerRepository: providerRepo,
      sessionRepository: sessionRepo,
      imageSessionRepository: imageRepo,
      videoSessionRepository: videoRepo,
      chatDefaultsRepository: chatDefaults,
      appearanceRepository: appearance,
      appLogRepository: appLogs,
      dataBackupService: dataBackup,
      generation: GenerationRuntime(),
      startupUpdateCheckDelay: Duration.zero,
      showBrandIntro: false,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: 'AI Studio',
      packageName: 'com.example.mobile_material',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets('shell shows NavigationBar with 对话', (tester) async {
    await _pumpApp(tester);

    expect(find.text('对话'), findsWidgets);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('unconfigured provider shows chat empty CTA', (tester) async {
    await _pumpApp(tester);

    expect(find.text('尚未配置提供商'), findsOneWidget);
    expect(find.text('去设置'), findsOneWidget);
  });

  testWidgets('configured provider shows composer', (tester) async {
    final providers = ProviderRepository(
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
    await providers.load();

    final sessions = ChatSessionRepository(
      storage: MemoryChatSessionStorage(),
    );
    await sessions.load();

    await _pumpApp(tester, providers: providers, sessions: sessions);

    expect(find.text('尚未配置提供商'), findsNothing);
    expect(find.text('去设置'), findsNothing);
    expect(find.text('还没有消息'), findsOneWidget);
    expect(find.text('在下方输入第一条消息，或打开会话列表新建。'), findsOneWidget);
    expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    expect(find.textContaining('gpt-test'), findsWidgets);
  });

  testWidgets('session list empty shows create CTA', (tester) async {
    var created = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => SessionListPage(
                          sessions: const [],
                          activeId: '',
                          onSelect: (_) {},
                          onCreate: () => created = true,
                          onDelete: (_) {},
                        ),
                      ),
                    );
                  },
                  child: const Text('open-sessions'),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open-sessions'));
    await tester.pumpAndSettle();

    expect(find.text('暂无会话'), findsOneWidget);
    expect(find.text('新建会话'), findsOneWidget);
    await tester.tap(find.text('新建会话'));
    await tester.pumpAndSettle();
    expect(created, isTrue);
  });

  testWidgets('unconfigured image provider shows empty CTA', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.text('生图'));
    await tester.pumpAndSettle();

    expect(find.text('尚未配置生图模型'), findsOneWidget);
    expect(find.text('去设置'), findsOneWidget);
  });

  testWidgets('configured image provider shows params composer',
      (tester) async {
    final providers = ProviderRepository(
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
              imageModel: 'gpt-image-1',
              enabled: true,
            ),
          ],
          activeProviderId: 'p1',
        ),
      ),
      connectionTester: StubProviderConnectionTester(),
    );
    await providers.load();

    await _pumpApp(tester, providers: providers);

    await tester.tap(find.text('生图'));
    await tester.pumpAndSettle();

    expect(find.text('尚未配置生图模型'), findsNothing);
    expect(find.text('参数'), findsOneWidget);
    expect(find.text('生成'), findsOneWidget);
    expect(find.text('从相册选择参考图'), findsOneWidget);
    expect(find.textContaining('gpt-image-1'), findsWidgets);
  });

  testWidgets('unconfigured video provider shows empty CTA', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.text('生视频'));
    await tester.pumpAndSettle();

    expect(find.text('尚未配置视频模型'), findsOneWidget);
    expect(find.text('去设置'), findsOneWidget);
  });

  testWidgets('configured video provider shows params composer',
      (tester) async {
    final providers = ProviderRepository(
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
              videoModel: 'sora-2',
              enabled: true,
            ),
          ],
          activeProviderId: 'p1',
        ),
      ),
      connectionTester: StubProviderConnectionTester(),
    );
    await providers.load();

    await _pumpApp(tester, providers: providers);

    await tester.tap(find.text('生视频'));
    await tester.pumpAndSettle();

    expect(find.text('尚未配置视频模型'), findsNothing);
    expect(find.text('参数'), findsOneWidget);
    expect(find.text('创建任务'), findsOneWidget);
    expect(find.textContaining('sora-2'), findsWidgets);
  });

  testWidgets('can switch to settings and see 提供商 tab', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    expect(find.text('提供商'), findsWidgets);
    expect(find.text('对话'), findsWidgets);
    expect(find.text('外观'), findsWidgets);
    expect(find.text('日志'), findsWidgets);
    expect(find.text('关于'), findsWidgets);
    expect(find.textContaining('点选切换当前提供商'), findsOneWidget);
    expect(find.text('编辑所选提供商'), findsOneWidget);
    expect(find.text('编辑提供商'), findsNothing);
  });

  testWidgets('providers tab empty/loading smoke with memory storage',
      (tester) async {
    final repo = ProviderRepository(
      storage: MemoryProviderStorage(
        const ProviderStoreSnapshot(providers: [], activeProviderId: ''),
      ),
      connectionTester: StubProviderConnectionTester(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsProvidersTab(repository: repo),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('暂无提供商'), findsOneWidget);
    expect(find.text('添加 OpenAI / xAI 或兼容源后即可对话与生成。'), findsOneWidget);
    expect(find.text('添加提供商'), findsWidgets);
    expect(find.byIcon(Icons.add), findsWidgets);

    await repo.load();
    await tester.pumpAndSettle();

    expect(find.text('暂无提供商'), findsNothing);
    expect(find.text('编辑提供商'), findsNothing);
    expect(find.text('编辑所选提供商'), findsOneWidget);
    expect(find.text('xAI Grok'), findsOneWidget);
    expect(find.byType(ListTile), findsWidgets);

    await tester.tap(find.text('xAI Grok'));
    await tester.pumpAndSettle();
    expect(find.text('编辑提供商'), findsNothing);

    await tester.tap(find.text('编辑所选提供商'));
    await tester.pumpAndSettle();
    expect(find.text('编辑提供商'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
  });

  testWidgets('session list items expose semantics labels', (tester) async {
    final providers = ProviderRepository(
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
    await providers.load();

    final sessions = ChatSessionRepository(
      storage: MemoryChatSessionStorage(),
    );
    await sessions.load();
    final created = await sessions.createSession(title: '无障碍会话');
    await sessions.setActive(created.id);

    await _pumpApp(tester, providers: providers, sessions: sessions);

    await tester.tap(find.byTooltip('会话列表'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('新建会话'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'无障碍会话')), findsWidgets);
  });

  testWidgets('composer send button exposes tooltip', (tester) async {
    final providers = ProviderRepository(
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
    await providers.load();

    final sessions = ChatSessionRepository(
      storage: MemoryChatSessionStorage(),
    );
    await sessions.load();

    await _pumpApp(tester, providers: providers, sessions: sessions);

    expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    expect(find.byTooltip('发送'), findsOneWidget);
    expect(find.bySemanticsLabel('消息输入'), findsWidgets);
  });

  testWidgets('image composer primary button exposes semantics', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImageComposer(
            prompt: '',
            onPromptChanged: (_) {},
            n: 1,
            onNChanged: (_) {},
            size: '1024x1024',
            onSizeChanged: (_) {},
            aspectRatio: '1:1',
            onAspectRatioChanged: (_) {},
            useAspectRatio: false,
            sizeOptions: const ['1024x1024'],
            aspectOptions: const ['1:1'],
            modelLabel: 'test-model',
            enabled: true,
            generating: false,
            onGenerate: () {},
            onStop: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.bySemanticsLabel('生成图片'), findsWidgets);
    expect(find.byTooltip('收起参数'), findsOneWidget);
  });

  testWidgets('update banner is a live region', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UpdateBanner(
            version: '9.9.9',
            onGoUpdate: _noop,
            onLater: _noop,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.bySemanticsLabel(RegExp(r'发现新版本 9\.9\.9')),
      findsWidgets,
    );
  });

  testWidgets('section switch keeps chat state via IndexedStack', (tester) async {
    await _pumpApp(tester);

    expect(find.text('尚未配置提供商'), findsOneWidget);
    await tester.tap(find.text('生图'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('尚未配置生图模型'), findsOneWidget);

    await tester.tap(find.text('对话'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('尚未配置提供商'), findsOneWidget);
  });

  testWidgets('root back shows exit confirm snackbar', (tester) async {
    await _pumpApp(tester);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('再按一次退出'), findsOneWidget);
    expect(find.text('对话'), findsWidgets);

    // 窗口过期后再按，应再次提示而非立刻离页。
    await tester.pump(const Duration(seconds: 3));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('再按一次退出'), findsOneWidget);
    expect(find.text('对话'), findsWidgets);
  });

  testWidgets('brand intro shows then dismisses on tap', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildMaterialLightTheme(),
        home: BrandIntroGate(
          displayDuration: const Duration(seconds: 30),
          fadeDuration: const Duration(milliseconds: 50),
          child: const Center(child: Text('shell-ready')),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('AI Studio'), findsOneWidget);
    expect(find.text('对话 · 生图 · 生视频'), findsOneWidget);
    expect(find.text('shell-ready'), findsOneWidget);

    await tester.tap(find.text('AI Studio'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(find.text('对话 · 生图 · 生视频'), findsNothing);
    expect(find.text('shell-ready'), findsOneWidget);
  });
}
