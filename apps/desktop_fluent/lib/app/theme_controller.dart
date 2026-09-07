import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:flutter/foundation.dart';

class ThemeController extends ChangeNotifier {
  ThemeController({AppearanceRepository? repository})
      : _repository = repository;

  final AppearanceRepository? _repository;

  ThemePreference _preference = ThemePreference.light;
  AppFontScale _fontScale = AppFontScale.standard;
  UiDensity _density = UiDensity.comfortable;

  AppearanceRepository? get appearanceRepository => _repository;

  ThemePreference get preference => _preference;
  AppFontScale get fontScale => _fontScale;
  UiDensity get density => _density;

  /// 从仓库同步当前外观（main 在 `appearanceRepo.load()` 后调用）。
  void loadFrom(AppearanceSettings settings) {
    final nextPref = ThemePreference.fromWire(settings.themePreference);
    final nextScale = AppFontScale.fromWire(settings.fontScale);
    final nextDensity = UiDensity.fromWire(settings.density);
    if (_preference == nextPref &&
        _fontScale == nextScale &&
        _density == nextDensity) {
      return;
    }
    _preference = nextPref;
    _fontScale = nextScale;
    _density = nextDensity;
    notifyListeners();
  }

  Future<void> setPreference(ThemePreference value) async {
    if (_preference == value) return;
    _preference = value;
    notifyListeners();
    await _persist();
  }

  Future<void> setFontScale(AppFontScale value) async {
    if (_fontScale == value) return;
    _fontScale = value;
    notifyListeners();
    await _persist();
  }

  Future<void> setDensity(UiDensity value) async {
    if (_density == value) return;
    _density = value;
    notifyListeners();
    await _persist();
  }

  /// 浅色 ↔ 深色循环。
  Future<void> cycleLightDark() => setPreference(_preference.toggled);

  Future<void> _persist() async {
    final repo = _repository;
    if (repo == null) return;
    await repo.update(
      themePreference: _preference.wire,
      fontScale: _fontScale.wire,
      density: _density.wire,
    );
  }
}
