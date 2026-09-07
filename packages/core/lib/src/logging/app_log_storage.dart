import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_log_entry.dart';

/// 运行日志存储抽象。
abstract class AppLogStorage {
  Future<List<AppLogEntry>> load();

  Future<void> save(List<AppLogEntry> entries);
}

/// SharedPreferences：`core.app_logs.v1` → JSON 数组。
class PrefsAppLogStorage implements AppLogStorage {
  PrefsAppLogStorage({SharedPreferences? prefs}) : _prefsOverride = prefs;

  static const prefsKey = 'core.app_logs.v1';

  final SharedPreferences? _prefsOverride;
  SharedPreferences? _prefs;

  Future<SharedPreferences> _ensurePrefs() async {
    return _prefs ??= _prefsOverride ?? await SharedPreferences.getInstance();
  }

  @override
  Future<List<AppLogEntry>> load() async {
    final prefs = await _ensurePrefs();
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map)
            AppLogEntry.fromJson(Map<String, dynamic>.from(item)),
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> save(List<AppLogEntry> entries) async {
    final prefs = await _ensurePrefs();
    final payload = entries.map((e) => e.toJson()).toList(growable: false);
    await prefs.setString(prefsKey, jsonEncode(payload));
  }
}

/// 内存存储（单元测试）。
class MemoryAppLogStorage implements AppLogStorage {
  MemoryAppLogStorage([List<AppLogEntry>? initial])
      : _entries = List<AppLogEntry>.from(initial ?? const []);

  List<AppLogEntry> _entries;

  List<AppLogEntry> get current => List.unmodifiable(_entries);

  @override
  Future<List<AppLogEntry>> load() async => List<AppLogEntry>.from(_entries);

  @override
  Future<void> save(List<AppLogEntry> entries) async {
    _entries = List<AppLogEntry>.from(entries);
  }
}
