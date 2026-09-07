import 'package:core/core.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('AppearanceSettings JSON roundtrip', () {
    const original = AppearanceSettings(
      themePreference: 'dark',
      fontScale: 'larger',
      density: 'compact',
      closeBehavior: 'tray',
    );
    final restored = AppearanceSettings.fromJson(original.toJson());
    expect(restored, original);
  });

  test('fromJson defaults closeBehavior when missing (compat)', () {
    final restored = AppearanceSettings.fromJson({
      'themePreference': 'dark',
      'fontScale': 'standard',
      'density': 'comfortable',
    });
    expect(restored.closeBehavior, AppearanceSettings.defaultCloseBehavior);
    expect(restored.themePreference, 'dark');
  });

  test('platformDefaultDensity: desktop comfortable, mobile compact', () {
    expect(
      AppearanceSettings.platformDefaultDensity(
        platform: TargetPlatform.windows,
      ),
      'comfortable',
    );
    expect(
      AppearanceSettings.platformDefaultDensity(
        platform: TargetPlatform.macOS,
      ),
      'comfortable',
    );
    expect(
      AppearanceSettings.platformDefaultDensity(
        platform: TargetPlatform.android,
      ),
      'compact',
    );
    expect(
      AppearanceSettings.platformDefaultDensity(platform: TargetPlatform.iOS),
      'compact',
    );
  });

  test('sanitized falls back for unknown wire', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final bad = const AppearanceSettings(
      themePreference: 'system',
      fontScale: 'huge',
      density: 'dense',
      closeBehavior: 'minimize',
    ).sanitized();
    expect(bad.themePreference, AppearanceSettings.defaultThemePreference);
    expect(bad.fontScale, AppearanceSettings.defaultFontScale);
    expect(bad.density, 'comfortable');
    expect(bad.closeBehavior, AppearanceSettings.defaultCloseBehavior);
  });

  test('sanitized unknown density uses mobile platform default', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final bad = const AppearanceSettings(density: 'dense').sanitized();
    expect(bad.density, 'compact');
  });

  test('MemoryAppearanceStorage roundtrip via repository', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final storage = MemoryAppearanceStorage();
    final repo = AppearanceRepository(storage: storage);
    await repo.load();
    expect(repo.settings, AppearanceSettings.recommended);
    expect(repo.settings.density, 'comfortable');

    await repo.update(
      themePreference: 'dark',
      fontScale: 'small',
      density: 'compact',
      closeBehavior: 'quit',
    );
    expect(repo.settings.themePreference, 'dark');
    expect(repo.settings.fontScale, 'small');
    expect(repo.settings.closeBehavior, 'quit');
    expect(storage.current.density, 'compact');

    final other = AppearanceRepository(storage: storage);
    await other.load();
    expect(other.settings, repo.settings);

    await other.resetToRecommended();
    expect(other.settings, AppearanceSettings.recommended);
    expect(other.settings.density, 'comfortable');
  });

  test('PrefsAppearanceStorage first load persists platform default', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = PrefsAppearanceStorage(prefs: prefs);
    final loaded = await storage.load();
    expect(loaded.density, 'compact');
    expect(prefs.getString(PrefsAppearanceStorage.prefsKey), isNotEmpty);

    // 已有 prefs 不被静默覆盖
    await storage.save(
      const AppearanceSettings(
        themePreference: 'dark',
        fontScale: 'smaller',
        density: 'comfortable',
        closeBehavior: 'ask',
      ),
    );
    final again = await storage.load();
    expect(again.themePreference, 'dark');
    expect(again.fontScale, 'smaller');
    expect(again.density, 'comfortable');
    expect(again.closeBehavior, 'ask');
  });

  test('PrefsAppearanceStorage roundtrip with injected prefs', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = PrefsAppearanceStorage(prefs: prefs);
    await storage.save(
      const AppearanceSettings(
        themePreference: 'dark',
        fontScale: 'smaller',
        density: 'comfortable',
        closeBehavior: 'ask',
      ),
    );
    final loaded = await storage.load();
    expect(loaded.themePreference, 'dark');
    expect(loaded.fontScale, 'smaller');
    expect(loaded.density, 'comfortable');
    expect(loaded.closeBehavior, 'ask');
    expect(prefs.getString(PrefsAppearanceStorage.prefsKey), isNotEmpty);
  });
}
