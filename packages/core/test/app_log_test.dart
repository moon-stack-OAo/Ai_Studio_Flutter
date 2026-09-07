import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('AppLogEntry JSON roundtrip', () {
    final original = AppLogEntry.create(
      level: AppLogLevel.warn,
      source: AppLogSources.chat,
      message: 'hello',
      at: 1725444123000,
      id: 'log_test01',
    );
    final restored = AppLogEntry.fromJson(original.toJson());
    expect(restored, original);
    expect(restored.level.label, 'WARN');
    expect(restored.sourceLabel, '对话');
  });

  test('append / query / clear via MemoryAppLogStorage', () async {
    final storage = MemoryAppLogStorage();
    final repo = AppLogRepository(storage: storage);
    await repo.load();
    expect(repo.totalCount, 0);

    await repo.append(
      level: AppLogLevel.info,
      source: AppLogSources.system,
      message: '应用启动',
      at: 1000,
    );
    await repo.append(
      level: AppLogLevel.error,
      source: AppLogSources.chat,
      message: '请求失败',
      at: 2000,
    );
    await repo.append(
      level: AppLogLevel.debug,
      source: AppLogSources.http,
      message: 'GET /v1/models',
      at: 1500,
    );

    expect(repo.totalCount, 3);
    expect(repo.entries.first.message, '请求失败');
    expect(repo.entries.map((e) => e.at).toList(), [2000, 1500, 1000]);

    final errors = repo.query(exactLevel: AppLogLevel.error);
    expect(errors, hasLength(1));
    expect(errors.first.source, AppLogSources.chat);

    final minWarn = repo.query(minLevel: AppLogLevel.warn);
    expect(minWarn, hasLength(1));

    final chatOnly = repo.query(source: AppLogSources.chat);
    expect(chatOnly, hasLength(1));

    final searched = repo.query(search: '启动');
    expect(searched, hasLength(1));
    expect(searched.first.source, AppLogSources.system);

    final visible = repo.formatVisible(repo.query());
    expect(visible, contains('ERROR · chat · 请求失败'));
    expect(visible, contains('INFO · system · 应用启动'));

    await repo.clear();
    expect(repo.totalCount, 0);
    expect(storage.current, isEmpty);
  });

  test('max 500 drops oldest', () async {
    final storage = MemoryAppLogStorage();
    final repo = AppLogRepository(storage: storage);
    await repo.load();
    for (var i = 0; i < AppLogRepository.maxEntries + 20; i++) {
      await repo.append(
        level: AppLogLevel.debug,
        source: AppLogSources.system,
        message: 'n=$i',
        at: i,
      );
    }
    expect(repo.totalCount, AppLogRepository.maxEntries);
    expect(repo.entries.first.message, 'n=${AppLogRepository.maxEntries + 19}');
    expect(repo.entries.last.message, 'n=20');
  });

  test('sanitize strips apiKey / Bearer / sk-', () async {
    final storage = MemoryAppLogStorage();
    final repo = AppLogRepository(storage: storage);
    await repo.load();

    final e1 = await repo.append(
      level: AppLogLevel.error,
      source: AppLogSources.http,
      message: 'Authorization: Bearer sk-abcdefghijklmnopqrstuvwxyz',
    );
    expect(e1.message, isNot(contains('sk-abcdefghijklmnopqrstuvwxyz')));
    expect(e1.message, contains('Bearer ***'));

    final e2 = await repo.append(
      level: AppLogLevel.error,
      source: AppLogSources.chat,
      message: 'apiKey=sk-1234567890abcdef fail',
    );
    expect(e2.message, isNot(contains('sk-1234567890abcdef')));
    expect(e2.message, contains('***'));

    final long = 'x' * (AppLogEntry.maxMessageLength + 100);
    final e3 = await repo.append(
      level: AppLogLevel.info,
      source: AppLogSources.system,
      message: long,
    );
    expect(e3.message.length, lessThanOrEqualTo(AppLogEntry.maxMessageLength + 1));
    expect(e3.message.endsWith('…'), isTrue);
  });

  test('MemoryAppLogStorage roundtrip via repository', () async {
    final storage = MemoryAppLogStorage();
    final repo = AppLogRepository(storage: storage);
    await repo.load();
    await repo.append(
      level: AppLogLevel.info,
      source: AppLogSources.updater,
      message: 'check ok',
      at: 42,
    );

    final other = AppLogRepository(storage: storage);
    await other.load();
    expect(other.totalCount, 1);
    expect(other.entries.first.message, 'check ok');
    expect(other.entries.first.source, AppLogSources.updater);
  });

  test('PrefsAppLogStorage roundtrip with injected prefs', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = PrefsAppLogStorage(prefs: prefs);
    await storage.save([
      AppLogEntry.create(
        level: AppLogLevel.warn,
        source: AppLogSources.image,
        message: 'poll slow',
        at: 99,
        id: 'log_prefs1',
      ),
    ]);
    final loaded = await storage.load();
    expect(loaded, hasLength(1));
    expect(loaded.first.message, 'poll slow');
    expect(prefs.getString(PrefsAppLogStorage.prefsKey), isNotEmpty);
  });

  test('formatTimestamp YYYY-MM-DD HH:mm:ss', () {
    final text = AppLogRepository.formatTimestamp(1725444128000);
    expect(RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$').hasMatch(text), isTrue);
  });
}
