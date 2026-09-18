import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('默认未解锁；unlock 后持久', () async {
    final prefs = HiddenPortalPrefs();
    await prefs.ensureLoaded();
    expect(prefs.unlocked, isFalse);

    await prefs.unlock();
    expect(prefs.unlocked, isTrue);

    final again = HiddenPortalPrefs();
    await again.ensureLoaded();
    expect(again.unlocked, isTrue);
  });

  test('lock 可关闭', () async {
    final now = DateTime(2026, 1, 1);
    SharedPreferences.setMockInitialValues({
      HiddenPortalPrefs.unlockedAtKey: now.millisecondsSinceEpoch,
    });
    final prefs = HiddenPortalPrefs(clock: () => now);
    await prefs.ensureLoaded();
    expect(prefs.unlocked, isTrue);

    await prefs.lock();
    expect(prefs.unlocked, isFalse);
  });

  test('超过 7 天自动过期', () async {
    final unlockedAt = DateTime(2026, 1, 1);
    var now = unlockedAt;
    SharedPreferences.setMockInitialValues({
      HiddenPortalPrefs.unlockedAtKey: unlockedAt.millisecondsSinceEpoch,
    });
    final prefs = HiddenPortalPrefs(clock: () => now);
    await prefs.ensureLoaded();
    expect(prefs.unlocked, isTrue);

    now = unlockedAt.add(const Duration(days: 7));
    await prefs.ensureLoaded();
    expect(prefs.unlocked, isFalse);
  });

  test('toggle 解锁后再隐藏', () async {
    final prefs = HiddenPortalPrefs();
    await prefs.ensureLoaded();
    expect(await prefs.toggle(), isTrue);
    expect(prefs.unlocked, isTrue);
    expect(await prefs.toggle(), isFalse);
    expect(prefs.unlocked, isFalse);
  });

  test('兼容旧 bool 键', () async {
    SharedPreferences.setMockInitialValues({
      HiddenPortalPrefs.unlockedKey: true,
    });
    final prefs = HiddenPortalPrefs(clock: () => DateTime(2026, 3, 1));
    await prefs.ensureLoaded();
    expect(prefs.unlocked, isTrue);
    expect(prefs.unlockedAt, DateTime(2026, 3, 1));
  });
}
