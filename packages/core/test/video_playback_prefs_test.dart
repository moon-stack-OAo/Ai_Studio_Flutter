import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VideoPlaybackPrefs', () {
    test('defaults: volume 100, unmuted', () {
      expect(VideoPlaybackPrefs.defaults.volume, 100);
      expect(VideoPlaybackPrefs.defaults.muted, isFalse);
      expect(VideoPlaybackPrefs.defaults.effectiveVolume, 100);
    });

    test('sanitized clamps volume to 0–100', () {
      expect(
        const VideoPlaybackPrefs(volume: 150).sanitized().volume,
        100,
      );
      expect(
        const VideoPlaybackPrefs(volume: -5).sanitized().volume,
        0,
      );
      expect(
        const VideoPlaybackPrefs(volume: double.nan).sanitized().volume,
        100,
      );
    });

    test('muted with volume 0 restores default volume for unmute', () {
      final p = const VideoPlaybackPrefs(volume: 0, muted: true).sanitized();
      expect(p.muted, isTrue);
      expect(p.volume, 100);
      expect(p.effectiveVolume, 0);
    });

    test('fromUi keeps restore volume while muted', () {
      final p = VideoPlaybackPrefs.fromUi(
        volume: 0,
        volumeBeforeMute: 42,
        muted: true,
      );
      expect(p.muted, isTrue);
      expect(p.volume, 42);
      expect(p.effectiveVolume, 0);
    });

    test('JSON roundtrip', () {
      const original = VideoPlaybackPrefs(volume: 33.5, muted: true);
      final restored = VideoPlaybackPrefs.fromJson(original.toJson());
      expect(restored, original.sanitized());
    });
  });

  group('MemoryVideoPlaybackPrefsStorage', () {
    test('load defaults when empty', () async {
      final storage = MemoryVideoPlaybackPrefsStorage();
      final loaded = await storage.load();
      expect(loaded, VideoPlaybackPrefs.defaults);
    });

    test('save/load roundtrip', () async {
      final storage = MemoryVideoPlaybackPrefsStorage();
      const next = VideoPlaybackPrefs(volume: 55, muted: true);
      await storage.save(next);
      expect(await storage.load(), next);
      expect(storage.current, next);
    });

    test('save clamps', () async {
      final storage = MemoryVideoPlaybackPrefsStorage();
      await storage.save(const VideoPlaybackPrefs(volume: 200, muted: false));
      expect(storage.current.volume, 100);
    });
  });

  group('PrefsVideoPlaybackPrefsStorage', () {
    late SharedPreferences prefs;
    late PrefsVideoPlaybackPrefsStorage storage;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      storage = PrefsVideoPlaybackPrefsStorage(prefs: prefs);
    });

    test('load defaults when missing', () async {
      final loaded = await storage.load();
      expect(loaded, VideoPlaybackPrefs.defaults);
      expect(prefs.getString(PrefsVideoPlaybackPrefsStorage.prefsKey), isNull);
    });

    test('save/load roundtrip via prefs key', () async {
      await storage.save(const VideoPlaybackPrefs(volume: 12, muted: true));
      final raw = prefs.getString(PrefsVideoPlaybackPrefsStorage.prefsKey);
      expect(raw, isNotNull);
      expect(raw, contains('"volume":12'));
      expect(raw, contains('"muted":true'));

      final again = PrefsVideoPlaybackPrefsStorage(prefs: prefs);
      final loaded = await again.load();
      expect(loaded.volume, 12);
      expect(loaded.muted, isTrue);
    });

    test('corrupt JSON falls back to defaults', () async {
      await prefs.setString(PrefsVideoPlaybackPrefsStorage.prefsKey, '{bad');
      expect(await storage.load(), VideoPlaybackPrefs.defaults);
    });
  });

  group('VideoPlaybackPrefsWriter', () {
    test('scheduleSave debounces and flush persists', () async {
      final mem = MemoryVideoPlaybackPrefsStorage();
      final writer = VideoPlaybackPrefsWriter(
        storage: mem,
        debounce: const Duration(milliseconds: 40),
      );
      writer.scheduleSave(const VideoPlaybackPrefs(volume: 10, muted: false));
      writer.scheduleSave(const VideoPlaybackPrefs(volume: 20, muted: true));
      expect(mem.current, VideoPlaybackPrefs.defaults);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(mem.current.volume, 20);
      expect(mem.current.muted, isTrue);
      expect(writer.cached?.volume, 20);
    });

    test('saveNow writes immediately', () async {
      final mem = MemoryVideoPlaybackPrefsStorage();
      final writer = VideoPlaybackPrefsWriter(
        storage: mem,
        debounce: const Duration(seconds: 5),
      );
      await writer.saveNow(const VideoPlaybackPrefs(volume: 7, muted: false));
      expect(mem.current.volume, 7);
    });
  });
}
