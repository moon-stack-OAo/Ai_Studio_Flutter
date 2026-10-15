import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_material/pages/settings/settings_about_tab.dart';
import 'package:mobile_material/pages/settings/settings_chat_defaults_tab.dart';
import 'package:mobile_material/update/mobile_update_controller.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _StatusUpdater extends MobileUpdateController {
  _StatusUpdater({bool ios = false}) : super(forceAndroid: !ios, forceIos: ios);
  UpdateCheckResult? result;
  bool checking = false;
  bool cachedUpdate = false;
  @override
  UpdateCheckResult? get lastCheck => result;
  @override
  bool get isChecking => checking;
  @override
  bool get hasAvailableUpdate => cachedUpdate;
  @override
  Future<void> ensurePrefsLoaded() async {}

  void refresh() => notifyListeners();
}

void main() {
  testWidgets('关于页区分更新状态，失败及未检查不显示已是最新', (tester) async {
    final providers = ProviderRepository(storage: MemoryProviderStorage());
    final appearance = AppearanceRepository(storage: MemoryAppearanceStorage());
    final defaults = ChatDefaultsRepository(
      storage: MemoryChatDefaultsStorage(),
    );
    final chats = ChatSessionRepository(storage: MemoryChatSessionStorage());
    final images = ImageSessionRepository(storage: MemoryImageSessionStorage());
    final videos = VideoSessionRepository(storage: MemoryVideoSessionStorage());
    await Future.wait([
      providers.load(),
      appearance.load(),
      defaults.load(),
      chats.load(),
      images.load(),
      videos.load(),
    ]);
    final updater = _StatusUpdater();
    final backup = DataBackupService(
      providers: providers,
      appearance: appearance,
      chatDefaults: defaults,
      chatSessions: chats,
      imageSessions: images,
      videoSessions: videos,
    );
    final info = PackageInfo(
      appName: 'AI Studio',
      packageName: 'studio.test',
      version: '1.0.0',
      buildNumber: '1',
    );
    Widget page(MobileUpdateController controller) => MaterialApp(
      theme: buildMaterialLightTheme(),
      home: Scaffold(
        body: SettingsAboutTab(
          dataBackupService: backup,
          updateController: controller,
          packageInfo: info,
        ),
      ),
    );
    await tester.pumpWidget(page(updater));
    await tester.pumpAndSettle();
    expect(find.text('尚未检查'), findsOneWidget);
    expect(find.text('已是最新'), findsNothing);
    updater.checking = true;
    updater.refresh();
    await tester.pump();
    expect(find.text('检查中…'), findsOneWidget);
    updater.checking = false;
    updater.cachedUpdate = true;
    for (final entry in {
      UpdateCheckStatus.failed: '检查失败',
      UpdateCheckStatus.notConfigured: '未配置更新源',
      UpdateCheckStatus.noPlatformAsset: '无平台安装包',
      UpdateCheckStatus.upToDate: '已是最新',
      UpdateCheckStatus.available: '有更新 9.0.0',
    }.entries) {
      updater.result = UpdateCheckResult(
        status: entry.key,
        currentVersion: '1.0.0',
        manifest: const UpdateManifest(version: '9.0.0'),
      );
      updater.refresh();
      await tester.pump();
      expect(find.text(entry.value), findsOneWidget);
      if (entry.key != UpdateCheckStatus.upToDate) {
        expect(find.text('已是最新'), findsNothing);
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    updater.dispose();
    final iosUpdater = _StatusUpdater(ios: true);
    await tester.pumpWidget(page(iosUpdater));
    await tester.pumpAndSettle();
    expect(find.text('内测渠道更新'), findsOneWidget);
    expect(find.text('已是最新'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    iosUpdater.dispose();
    await providers.waitForPersist();
    for (final repository in [
      providers,
      appearance,
      defaults,
      chats,
      images,
      videos,
    ]) {
      repository.dispose();
    }
  });

  testWidgets('对话默认保留冲突草稿，需显式确认才覆盖导入内容', (tester) async {
    final repository = ChatDefaultsRepository(
      storage: MemoryChatDefaultsStorage(),
    );
    await repository.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildMaterialLightTheme(),
        home: Scaffold(body: SettingsChatDefaultsTab(repository: repository)),
      ),
    );
    await tester.pumpAndSettle();
    final system = find.byType(TextField).first;
    await tester.enterText(system, '本机草稿');
    await repository.save(const ChatDefaults(systemPrompt: '导入内容'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(system).controller!.text, '本机草稿');
    final save = find.text('保存默认');
    await tester.scrollUntilVisible(
      save,
      250,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('覆盖最新配置？'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(repository.defaults.systemPrompt, '导入内容');
    await tester.scrollUntilVisible(
      save,
      250,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(save);
    await tester.pumpAndSettle();
    await tester.tap(find.text('覆盖保存'));
    await tester.pumpAndSettle();
    expect(repository.defaults.systemPrompt, '本机草稿');
    await tester.pumpWidget(const SizedBox.shrink());
    repository.dispose();
  });
}
