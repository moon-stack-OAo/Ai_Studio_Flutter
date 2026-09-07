import 'package:flutter/foundation.dart';

import 'appearance_settings.dart';
import 'appearance_storage.dart';

/// 外观设置仓库（ChangeNotifier）。
class AppearanceRepository extends ChangeNotifier {
  AppearanceRepository({required AppearanceStorage storage})
      : _storage = storage;

  final AppearanceStorage _storage;

  AppearanceSettings _settings = AppearanceSettings.recommended;
  bool _loaded = false;
  bool _loading = false;
  String? _lastError;

  bool get isLoaded => _loaded;
  bool get isLoading => _loading;
  String? get lastError => _lastError;

  AppearanceSettings get settings => _settings;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _lastError = null;
    notifyListeners();
    try {
      _settings = (await _storage.load()).sanitized();
      _loaded = true;
    } catch (e) {
      _lastError = e.toString();
      _settings = AppearanceSettings.recommended;
      _loaded = true;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> save(AppearanceSettings next) async {
    final sanitized = next.sanitized();
    _settings = sanitized;
    notifyListeners();
    try {
      await _storage.save(sanitized);
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> update({
    String? themePreference,
    String? fontScale,
    String? density,
    String? closeBehavior,
  }) {
    return save(
      _settings.copyWith(
        themePreference: themePreference,
        fontScale: fontScale,
        density: density,
        closeBehavior: closeBehavior,
      ),
    );
  }

  Future<void> resetToRecommended() => save(AppearanceSettings.recommended);
}
