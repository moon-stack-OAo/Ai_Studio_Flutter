import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'version_compare.dart';

/// 更新相关用户偏好（自动检查 / 跳过版本 / 可用版本角标）。
///
/// SharedPreferences keys：
/// - `core.update.auto_check.v1` → bool（默认 true）
/// - `core.update.skipped_version.v1` → 规范化版本
/// - `core.update.available_version.v1` → 规范化版本
///
/// 兼容旧键 `core.update_banner.dismissed_version.v1`：首次读 skipped 时若新键
/// 为空则迁移为 skipped（旧「稍后」语义并入「跳过」以免丢失用户意图）。
class UpdatePrefs extends ChangeNotifier {
  UpdatePrefs({SharedPreferences? prefs}) : _prefsOverride = prefs;

  static const autoCheckKey = 'core.update.auto_check.v1';
  static const skippedVersionKey = 'core.update.skipped_version.v1';
  static const availableVersionKey = 'core.update.available_version.v1';

  /// 旧横幅「稍后」键；仅用于一次性迁移到 [skippedVersionKey]。
  static const legacyDismissedVersionKey =
      'core.update_banner.dismissed_version.v1';

  final SharedPreferences? _prefsOverride;
  SharedPreferences? _prefs;

  bool _loaded = false;
  bool _autoCheckUpdate = true;
  String? _skippedUpdateVersion;
  String? _availableUpdateVersion;

  bool get isLoaded => _loaded;

  bool get autoCheckUpdate => _autoCheckUpdate;

  String? get skippedUpdateVersion => _skippedUpdateVersion;

  String? get availableUpdateVersion => _availableUpdateVersion;

  /// 有可用更新且未被跳过（驱动设置入口 NEW 角标）。
  bool get hasAvailableUpdate {
    final available = _availableUpdateVersion;
    if (available == null || available.isEmpty) return false;
    final skipped = _skippedUpdateVersion;
    if (skipped == null || skipped.isEmpty) return true;
    return available != skipped;
  }

  Future<SharedPreferences> _ensurePrefs() async {
    return _prefs ??= _prefsOverride ?? await SharedPreferences.getInstance();
  }

  Future<void> load() async {
    final prefs = await _ensurePrefs();
    _autoCheckUpdate = prefs.getBool(autoCheckKey) ?? true;

    var skipped = _normalizeOrNull(prefs.getString(skippedVersionKey));
    if (skipped == null) {
      final legacy = _normalizeOrNull(prefs.getString(legacyDismissedVersionKey));
      if (legacy != null) {
        skipped = legacy;
        await prefs.setString(skippedVersionKey, legacy);
        await prefs.remove(legacyDismissedVersionKey);
      }
    }
    _skippedUpdateVersion = skipped;
    _availableUpdateVersion =
        _normalizeOrNull(prefs.getString(availableVersionKey));
    _loaded = true;
    notifyListeners();
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    await load();
  }

  Future<void> setAutoCheckUpdate(bool value) async {
    await ensureLoaded();
    if (_autoCheckUpdate == value) return;
    _autoCheckUpdate = value;
    final prefs = await _ensurePrefs();
    await prefs.setBool(autoCheckKey, value);
    notifyListeners();
  }

  /// 静默检查是否应对该版本弹窗/写角标（已跳过同版本则 false）。
  Future<bool> shouldPromptFor(String? availableVersion) async {
    await ensureLoaded();
    final available = normalizeVersion(availableVersion);
    if (available.isEmpty) return false;
    final skipped = _skippedUpdateVersion;
    if (skipped == null || skipped.isEmpty) return true;
    return available != skipped;
  }

  Future<void> setAvailableUpdate(String? version) async {
    await ensureLoaded();
    final normalized = _normalizeOrNull(version);
    if (_availableUpdateVersion == normalized) return;
    _availableUpdateVersion = normalized;
    final prefs = await _ensurePrefs();
    if (normalized == null) {
      await prefs.remove(availableVersionKey);
    } else {
      await prefs.setString(availableVersionKey, normalized);
    }
    notifyListeners();
  }

  Future<void> clearAvailableUpdate() async {
    await setAvailableUpdate(null);
  }

  /// 「跳过此版本」：持久化 skipped，并清除角标用的 available。
  Future<void> skipUpdateVersion(String? version) async {
    await ensureLoaded();
    final normalized = _normalizeOrNull(version);
    if (normalized == null) return;
    _skippedUpdateVersion = normalized;
    _availableUpdateVersion = null;
    final prefs = await _ensurePrefs();
    await prefs.setString(skippedVersionKey, normalized);
    await prefs.remove(availableVersionKey);
    // 清理旧键，避免下次迁移覆盖。
    await prefs.remove(legacyDismissedVersionKey);
    notifyListeners();
  }

  Future<void> clearSkippedUpdateVersion() async {
    await ensureLoaded();
    if (_skippedUpdateVersion == null) return;
    _skippedUpdateVersion = null;
    final prefs = await _ensurePrefs();
    await prefs.remove(skippedVersionKey);
    await prefs.remove(legacyDismissedVersionKey);
    notifyListeners();
  }

  String? _normalizeOrNull(String? raw) {
    if (raw == null) return null;
    final normalized = normalizeVersion(raw);
    return normalized.isEmpty ? null : normalized;
  }
}
