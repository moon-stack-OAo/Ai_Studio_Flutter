import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:desktop_fluent/pages/settings/settings_about_page.dart';

class _BrokenHistory extends MemoryChatSessionStorage
    implements RecoverableHistoryStorage<ChatStoreSnapshot> {
  bool broken = true;
  int recoveries = 0;
  @override
  HistoryRecoveryState get recoveryState =>
      broken ? HistoryRecoveryState.damaged : HistoryRecoveryState.recovered;
  @override
  bool get writesBlocked => broken;
  @override
  Future<ChatStoreSnapshot> load() async =>
      throw const HistoryStorageException();
  @override
  Future<ChatStoreSnapshot> recover() async {
    recoveries++;
    broken = false;
    return const ChatStoreSnapshot(
      sessions: [
        ChatSession(id: 'restored', title: '恢复会话', createdAt: 1, updatedAt: 1),
      ],
      activeId: 'restored',
    );
  }

  @override
  Future<void> replaceHistory(ChatStoreSnapshot snapshot) async =>
      save(snapshot);
  @override
  Future<void> clearHistory(ChatStoreSnapshot empty) async => save(empty);
}

void main() {
  testWidgets('历史损坏安全提示与明确恢复入口', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = _BrokenHistory();
    final chats = ChatSessionRepository(storage: storage);
    final images = ImageSessionRepository(storage: MemoryImageSessionStorage());
    final videos = VideoSessionRepository(storage: MemoryVideoSessionStorage());
    final providers = ProviderRepository(storage: MemoryProviderStorage());
    final appearance = AppearanceRepository(storage: MemoryAppearanceStorage());
    final defaults = ChatDefaultsRepository(
      storage: MemoryChatDefaultsStorage(),
    );
    await Future.wait([
      chats.load(),
      images.load(),
      videos.load(),
      providers.load(),
      appearance.load(),
      defaults.load(),
    ]);
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
      packageName: 'test',
      version: '1',
      buildNumber: '1',
    );
    await tester.pumpWidget(
      FluentApp(
        home: SettingsAboutPage(
          appearanceRepository: appearance,
          dataBackupService: backup,
          packageInfo: info,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.text('重试恢复历史');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    expect(find.textContaining('历史数据读取异常'), findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(storage.recoveries, 1);
    expect(chats.activeId, 'restored');
    expect(find.textContaining('已从有效快照恢复历史'), findsOneWidget);
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await providers.waitForPersist();
    for (final repo in [
      chats,
      images,
      videos,
      providers,
      appearance,
      defaults,
    ]) {
      repo.dispose();
    }
  });
}
