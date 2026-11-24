import 'package:core/core.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
import 'package:desktop_fluent/pages/settings/settings_about_page.dart';

class _FailStorage extends MemoryAppearanceStorage {
  bool fail = false;
  @override
  Future<void> save(AppearanceSettings settings) async {
    if (fail) throw StateError('SENSITIVE_SENTINEL');
    await super.save(settings);
  }
}

void main() {
 for (final scenario in ['cancel', 'stale', 'partial']) {
  testWidgets('backup preview $scenario is safe', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1280, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final providers = ProviderRepository(storage: MemoryProviderStorage());
    final storage = _FailStorage();
    final appearance = AppearanceRepository(storage: storage);
    final defaults = ChatDefaultsRepository(storage: MemoryChatDefaultsStorage());
    final chats = ChatSessionRepository(storage: MemoryChatSessionStorage());
    final images = ImageSessionRepository(storage: MemoryImageSessionStorage());
    final videos = VideoSessionRepository(storage: MemoryVideoSessionStorage());
    await Future.wait([providers.load(), appearance.load(), defaults.load(), chats.load(), images.load(), videos.load()]);
    final backup = DataBackupService(providers: providers, appearance: appearance, chatDefaults: defaults, chatSessions: chats, imageSessions: images, videoSessions: videos);
    final raw = await backup.exportBackupJson();
    final info = PackageInfo(appName: 'test', packageName: 'test', version: '1', buildNumber: '1');
    await tester.pumpWidget(FluentApp(home: SettingsAboutPage(appearanceRepository: appearance, dataBackupService: backup, packageInfo: info, backupReader: () async => raw)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('导入设置')); await tester.tap(find.text('导入设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入').last);
    await tester.pumpAndSettle();
    expect(find.text('导入预览'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getString('core.backup_import_progress.v1'), isNull);
    if (scenario == 'cancel') {
      await tester.tap(find.text('取消').last);
    } else {
      if (scenario == 'stale') await defaults.save(const ChatDefaults(systemPrompt: 'changed'));
      if (scenario == 'partial') storage.fail = true;
      await tester.tap(find.text('确认导入'));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    if (scenario == 'stale') {
      expect(find.textContaining('本机数据已变更'), findsOneWidget);
      expect(defaults.defaults.systemPrompt, 'changed');
    }
    if (scenario == 'partial') {
      expect(find.textContaining('写入结果未知'), findsOneWidget);
      expect(find.textContaining('SENSITIVE_SENTINEL'), findsNothing);
    } else {
      expect((await SharedPreferences.getInstance()).getString('core.backup_import_progress.v1'), isNull);
    }
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpWidget(const SizedBox.shrink());
    await providers.waitForPersist();
    for (final r in [providers, appearance, defaults, chats, images, videos]) { r.dispose(); }
  });
 }
}
