import 'package:flutter/material.dart' show ThemeMode;

/// 外观主题偏好（SHELL-THEME / SET-APPEARANCE）。
/// 当前仅浅色 / 深色；跟随系统暂不提供入口。
enum ThemePreference {
  light,
  dark;

  ThemeMode get themeMode => switch (this) {
        ThemePreference.light => ThemeMode.light,
        ThemePreference.dark => ThemeMode.dark,
      };

  String get label => switch (this) {
        ThemePreference.light => '浅色',
        ThemePreference.dark => '深色',
      };

  String get wire => name;

  ThemePreference get toggled => switch (this) {
        ThemePreference.light => ThemePreference.dark,
        ThemePreference.dark => ThemePreference.light,
      };

  static ThemePreference fromWire(String? value) {
    if (value == null || value.isEmpty) return ThemePreference.light;
    for (final item in ThemePreference.values) {
      if (item.wire == value) return item;
    }
    return ThemePreference.light;
  }
}
