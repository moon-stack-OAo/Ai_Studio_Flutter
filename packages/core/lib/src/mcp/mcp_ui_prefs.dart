import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 对话页 MCP 提示相关偏好（本机）。
///
/// SharedPreferences：
/// - `core.mcp.dismiss_unconfigured_hint.v1` → bool
///   用户关闭「未配置已启用业务 MCP」横幅后记住，不再提示；
///   一旦再次启用任一 Server，自动清除，以便日后清空配置时仍可提醒。
class McpUiPrefs extends ChangeNotifier {
  McpUiPrefs({SharedPreferences? prefs}) : _prefsOverride = prefs;

  static const dismissUnconfiguredHintKey =
      'core.mcp.dismiss_unconfigured_hint.v1';

  final SharedPreferences? _prefsOverride;
  SharedPreferences? _prefs;

  bool _loaded = false;
  bool _dismissUnconfiguredHint = false;

  bool get isLoaded => _loaded;

  bool get dismissUnconfiguredHint => _dismissUnconfiguredHint;

  Future<SharedPreferences> _ensurePrefs() async {
    return _prefs ??= _prefsOverride ?? await SharedPreferences.getInstance();
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await _ensurePrefs();
    _dismissUnconfiguredHint =
        prefs.getBool(dismissUnconfiguredHintKey) ?? false;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setDismissUnconfiguredHint(bool value) async {
    await ensureLoaded();
    if (_dismissUnconfiguredHint == value) return;
    final prefs = await _ensurePrefs();
    _dismissUnconfiguredHint = value;
    await prefs.setBool(dismissUnconfiguredHintKey, value);
    notifyListeners();
  }

  Future<void> dismissUnconfiguredHintBanner() =>
      setDismissUnconfiguredHint(true);

  /// 用户启用了 MCP Server 后调用，恢复「未配置」提醒资格。
  Future<void> clearDismissUnconfiguredHint() =>
      setDismissUnconfiguredHint(false);
}
