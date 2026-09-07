import 'package:shared_preferences/shared_preferences.dart';

import 'version_compare.dart';

/// 启动更新横幅「稍后」偏好：记住已忽略的远端版本。
///
/// SharedPreferences：`core.update_banner.dismissed_version.v1` → 规范化版本字符串。
/// 同版本不再提示；更高版本再次提示。
class UpdateBannerPrefs {
  UpdateBannerPrefs({SharedPreferences? prefs}) : _prefsOverride = prefs;

  static const prefsKey = 'core.update_banner.dismissed_version.v1';

  final SharedPreferences? _prefsOverride;
  SharedPreferences? _prefs;

  Future<SharedPreferences> _ensurePrefs() async {
    return _prefs ??= _prefsOverride ?? await SharedPreferences.getInstance();
  }

  Future<String?> loadDismissedVersion() async {
    final prefs = await _ensurePrefs();
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.trim().isEmpty) return null;
    final normalized = normalizeVersion(raw);
    return normalized.isEmpty ? null : normalized;
  }

  /// 是否应对 [availableVersion] 显示横幅（相对已忽略版本更高，或从未忽略）。
  Future<bool> shouldShowFor(String? availableVersion) async {
    final available = normalizeVersion(availableVersion);
    if (available.isEmpty) return false;
    final dismissed = await loadDismissedVersion();
    if (dismissed == null || dismissed.isEmpty) return true;
    return isRemoteNewer(available, dismissed);
  }

  Future<void> dismissVersion(String? version) async {
    final normalized = normalizeVersion(version);
    if (normalized.isEmpty) return;
    final prefs = await _ensurePrefs();
    await prefs.setString(prefsKey, normalized);
  }

  Future<void> clear() async {
    final prefs = await _ensurePrefs();
    await prefs.remove(prefsKey);
  }
}
