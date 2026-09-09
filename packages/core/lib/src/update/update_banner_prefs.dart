import 'update_prefs.dart';

/// 兼容旧 API：横幅「稍后」曾写入 dismissed version。
///
/// 现已并入 [UpdatePrefs] 的「跳过此版本」语义。新代码请直接使用 [UpdatePrefs]。
class UpdateBannerPrefs {
  UpdateBannerPrefs({UpdatePrefs? prefs})
      : _prefs = prefs ?? UpdatePrefs();

  static const prefsKey = UpdatePrefs.legacyDismissedVersionKey;

  final UpdatePrefs _prefs;

  UpdatePrefs get updatePrefs => _prefs;

  Future<String?> loadDismissedVersion() async {
    await _prefs.ensureLoaded();
    return _prefs.skippedUpdateVersion;
  }

  Future<bool> shouldShowFor(String? availableVersion) {
    return _prefs.shouldPromptFor(availableVersion);
  }

  Future<void> dismissVersion(String? version) {
    return _prefs.skipUpdateVersion(version);
  }

  Future<void> clear() => _prefs.clearSkippedUpdateVersion();
}
