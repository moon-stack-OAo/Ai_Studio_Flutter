import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'appearance_settings.dart';

/// 外观设置存储抽象。
abstract class AppearanceStorage {
  Future<AppearanceSettings> load();

  Future<void> save(AppearanceSettings settings);
}

/// SharedPreferences：`core.appearance.v1` → JSON。
class PrefsAppearanceStorage implements AppearanceStorage {
  PrefsAppearanceStorage({SharedPreferences? prefs}) : _prefsOverride = prefs;

  static const prefsKey = 'core.appearance.v1';

  final SharedPreferences? _prefsOverride;
  SharedPreferences? _prefs;

  Future<SharedPreferences> _ensurePrefs() async {
    return _prefs ??= _prefsOverride ?? await SharedPreferences.getInstance();
  }

  @override
  Future<AppearanceSettings> load() async {
    final prefs = await _ensurePrefs();
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) {
      // 首装：按平台写入推荐密度，避免后续跨端/重置歧义。
      final recommended = AppearanceSettings.recommended;
      await save(recommended);
      return recommended;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return AppearanceSettings.recommended;
      return AppearanceSettings.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return AppearanceSettings.recommended;
    }
  }

  @override
  Future<void> save(AppearanceSettings settings) async {
    final prefs = await _ensurePrefs();
    await prefs.setString(
      prefsKey,
      jsonEncode(settings.sanitized().toJson()),
    );
  }
}

/// 内存存储（单元测试）。
class MemoryAppearanceStorage implements AppearanceStorage {
  MemoryAppearanceStorage([AppearanceSettings? initial])
      : _settings = (initial ?? AppearanceSettings.recommended).sanitized();

  AppearanceSettings _settings;

  AppearanceSettings get current => _settings;

  @override
  Future<AppearanceSettings> load() async => _settings;

  @override
  Future<void> save(AppearanceSettings settings) async {
    _settings = settings.sanitized();
  }
}
