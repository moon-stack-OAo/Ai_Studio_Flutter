import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// VID-PLAYER 音量偏好（跨启动持久化）。
///
/// SharedPreferences：`core.video_playback.v1` →
/// `{ "volume": 100.0, "muted": false }`
class VideoPlaybackPrefs {
  const VideoPlaybackPrefs({
    this.volume = defaultVolume,
    this.muted = defaultMuted,
  });

  static const defaultVolume = 100.0;
  static const defaultMuted = false;

  static const defaults = VideoPlaybackPrefs();

  /// 0–100；静音时仍保存取消静音后应恢复的音量。
  final double volume;

  final bool muted;

  /// 实际交给播放内核的音量。
  double get effectiveVolume => muted ? 0.0 : volume;

  VideoPlaybackPrefs copyWith({double? volume, bool? muted}) {
    return VideoPlaybackPrefs(
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
    );
  }

  VideoPlaybackPrefs sanitized() {
    final raw = volume;
    final clamped = (raw.isFinite ? raw : defaultVolume).clamp(0.0, 100.0);
    // 静音且存了 0：恢复默认 100，避免取消静音仍为 0。
    final restored = muted && clamped <= 0 ? defaultVolume : clamped.toDouble();
    return VideoPlaybackPrefs(volume: restored, muted: muted);
  }

  Map<String, dynamic> toJson() => {
        'volume': volume,
        'muted': muted,
      };

  factory VideoPlaybackPrefs.fromJson(Map<String, dynamic> json) {
    final volumeRaw = json['volume'];
    final double volume;
    if (volumeRaw is num) {
      volume = volumeRaw.toDouble();
    } else if (volumeRaw is String) {
      volume = double.tryParse(volumeRaw) ?? defaultVolume;
    } else {
      volume = defaultVolume;
    }
    final mutedRaw = json['muted'];
    final muted = mutedRaw is bool
        ? mutedRaw
        : (mutedRaw is num ? mutedRaw != 0 : defaultMuted);
    return VideoPlaybackPrefs(volume: volume, muted: muted).sanitized();
  }

  /// 从播放壳 UI 状态构造（静音时 volume 取取消静音恢复值）。
  factory VideoPlaybackPrefs.fromUi({
    required double volume,
    required double volumeBeforeMute,
    required bool muted,
  }) {
    final restore = volumeBeforeMute <= 0 ? defaultVolume : volumeBeforeMute;
    final level = muted
        ? restore
        : (volume <= 0 ? restore : volume);
    return VideoPlaybackPrefs(volume: level, muted: muted).sanitized();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VideoPlaybackPrefs &&
          volume == other.volume &&
          muted == other.muted;

  @override
  int get hashCode => Object.hash(volume, muted);
}

/// 音量偏好存储抽象。
abstract class VideoPlaybackPrefsStorage {
  Future<VideoPlaybackPrefs> load();

  Future<void> save(VideoPlaybackPrefs prefs);
}

/// SharedPreferences：`core.video_playback.v1` → JSON。
class PrefsVideoPlaybackPrefsStorage implements VideoPlaybackPrefsStorage {
  PrefsVideoPlaybackPrefsStorage({SharedPreferences? prefs})
      : _prefsOverride = prefs;

  static const prefsKey = 'core.video_playback.v1';

  final SharedPreferences? _prefsOverride;
  SharedPreferences? _prefs;

  Future<SharedPreferences> _ensurePrefs() async {
    return _prefs ??= _prefsOverride ?? await SharedPreferences.getInstance();
  }

  @override
  Future<VideoPlaybackPrefs> load() async {
    final prefs = await _ensurePrefs();
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) {
      return VideoPlaybackPrefs.defaults;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return VideoPlaybackPrefs.defaults;
      return VideoPlaybackPrefs.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return VideoPlaybackPrefs.defaults;
    }
  }

  @override
  Future<void> save(VideoPlaybackPrefs prefs) async {
    final store = await _ensurePrefs();
    await store.setString(
      prefsKey,
      jsonEncode(prefs.sanitized().toJson()),
    );
  }
}

/// 内存存储（单元测试）。
class MemoryVideoPlaybackPrefsStorage implements VideoPlaybackPrefsStorage {
  MemoryVideoPlaybackPrefsStorage([VideoPlaybackPrefs? initial])
      : _prefs = (initial ?? VideoPlaybackPrefs.defaults).sanitized();

  VideoPlaybackPrefs _prefs;

  VideoPlaybackPrefs get current => _prefs;

  @override
  Future<VideoPlaybackPrefs> load() async => _prefs;

  @override
  Future<void> save(VideoPlaybackPrefs prefs) async {
    _prefs = prefs.sanitized();
  }
}

/// 跨 Player 壳共享的防抖写入，避免 panel / dialog / fullscreen 互相覆盖打架。
final class VideoPlaybackPrefsWriter {
  VideoPlaybackPrefsWriter({
    VideoPlaybackPrefsStorage? storage,
    this.debounce = const Duration(milliseconds: 280),
  }) : _storage = storage ?? PrefsVideoPlaybackPrefsStorage();

  /// 双端默认单例（同键语义）。
  static VideoPlaybackPrefsWriter instance = VideoPlaybackPrefsWriter();

  /// 测试重置。
  static void debugResetInstance([VideoPlaybackPrefsWriter? next]) {
    instance = next ?? VideoPlaybackPrefsWriter();
  }

  final VideoPlaybackPrefsStorage _storage;
  final Duration debounce;

  Timer? _timer;
  VideoPlaybackPrefs? _pending;
  VideoPlaybackPrefs? _cached;

  /// 优先返回未落盘的 pending / 内存缓存，避免多壳互读时踩到旧盘值。
  Future<VideoPlaybackPrefs> load() async {
    final pending = _pending;
    if (pending != null) return pending;
    final cached = _cached;
    if (cached != null) return cached;
    final loaded = (await _storage.load()).sanitized();
    _cached = loaded;
    return loaded;
  }

  /// 最近一次 load / 成功写入的缓存；未 load 过则为 null。
  VideoPlaybackPrefs? get cached => _cached;

  void scheduleSave(VideoPlaybackPrefs prefs) {
    _pending = prefs.sanitized();
    _cached = _pending;
    _timer?.cancel();
    _timer = Timer(debounce, () {
      unawaited(flush());
    });
  }

  Future<void> saveNow(VideoPlaybackPrefs prefs) async {
    _timer?.cancel();
    _timer = null;
    final next = prefs.sanitized();
    _pending = null;
    _cached = next;
    await _storage.save(next);
  }

  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    final pending = _pending;
    if (pending == null) return;
    _pending = null;
    _cached = pending;
    await _storage.save(pending);
  }
}
