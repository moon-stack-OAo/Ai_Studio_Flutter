import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/material.dart' show Brightness, Color, ThemeExtension;

/// Fluent 设计 token（亮色 Claude 向 / 暗色 Cursor 向）。
@immutable
class FluentTokens extends ThemeExtension<FluentTokens> {
  const FluentTokens({
    required this.brightness,
    required this.canvas,
    required this.surface,
    required this.surfaceMuted,
    required this.surfaceElevated,
    required this.ink,
    required this.inkSecondary,
    required this.inkMuted,
    required this.border,
    required this.primary,
    required this.primaryPressed,
    required this.onPrimary,
    required this.success,
    required this.danger,
    required this.warning,
    required this.focusRing,
    required this.navWidth,
    required this.settingsCatWidth,
    required this.fontFamily,
    required this.monoFontFamily,
  });

  final Brightness brightness;
  final Color canvas;
  final Color surface;
  final Color surfaceMuted;
  final Color surfaceElevated;
  final Color ink;
  final Color inkSecondary;
  final Color inkMuted;
  final Color border;
  final Color primary;
  final Color primaryPressed;
  final Color onPrimary;
  final Color success;
  final Color danger;
  final Color warning;
  final Color focusRing;
  final double navWidth;
  final double settingsCatWidth;
  final String fontFamily;
  final String monoFontFamily;

  static const String fontStackFamily = 'Segoe UI Variable';
  static const String monoStackFamily = 'Cascadia Code';

  /// Light — Claude 向
  static const FluentTokens light = FluentTokens(
    brightness: Brightness.light,
    canvas: Color(0xFFFAF9F5),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFEFEEEB),
    surfaceElevated: Color(0xFFEFE9DE),
    ink: Color(0xFF141413),
    inkSecondary: Color(0xFF3D3D3A),
    inkMuted: Color(0xFF6C6A64),
    border: Color(0xFFE7E6E1),
    primary: Color(0xFFD97757),
    primaryPressed: Color(0xFFA9583E),
    onPrimary: Color(0xFFFFFFFF),
    success: Color(0xFF3F6F4E),
    danger: Color(0xFFB42318),
    warning: Color(0xFFB45309),
    focusRing: Color(0x66D97757),
    navWidth: 56,
    settingsCatWidth: 260,
    fontFamily: fontStackFamily,
    monoFontFamily: monoStackFamily,
  );

  /// Dark — Cursor 向（primary 为冷蓝，与亮色暖珊瑚不共用 hue）
  static const FluentTokens dark = FluentTokens(
    brightness: Brightness.dark,
    canvas: Color(0xFF0A0A0A),
    surface: Color(0xFF141414),
    surfaceMuted: Color(0xFF18181B),
    surfaceElevated: Color(0xFF1C1C1C),
    ink: Color(0xFFFAFAFA),
    inkSecondary: Color(0xFFA1A1AA),
    inkMuted: Color(0xFF71717A),
    border: Color(0xFF27272A),
    primary: Color(0xFF3B82F6),
    primaryPressed: Color(0xFF2563EB),
    onPrimary: Color(0xFFFFFFFF),
    success: Color(0xFF3F6F4E),
    danger: Color(0xFFEF4444),
    warning: Color(0xFFF59E0B),
    focusRing: Color(0x663B82F6),
    navWidth: 56,
    settingsCatWidth: 260,
    fontFamily: fontStackFamily,
    monoFontFamily: monoStackFamily,
  );

  static FluentTokens ofBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  @override
  FluentTokens copyWith({
    Brightness? brightness,
    Color? canvas,
    Color? surface,
    Color? surfaceMuted,
    Color? surfaceElevated,
    Color? ink,
    Color? inkSecondary,
    Color? inkMuted,
    Color? border,
    Color? primary,
    Color? primaryPressed,
    Color? onPrimary,
    Color? success,
    Color? danger,
    Color? warning,
    Color? focusRing,
    double? navWidth,
    double? settingsCatWidth,
    String? fontFamily,
    String? monoFontFamily,
  }) {
    return FluentTokens(
      brightness: brightness ?? this.brightness,
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      ink: ink ?? this.ink,
      inkSecondary: inkSecondary ?? this.inkSecondary,
      inkMuted: inkMuted ?? this.inkMuted,
      border: border ?? this.border,
      primary: primary ?? this.primary,
      primaryPressed: primaryPressed ?? this.primaryPressed,
      onPrimary: onPrimary ?? this.onPrimary,
      success: success ?? this.success,
      danger: danger ?? this.danger,
      warning: warning ?? this.warning,
      focusRing: focusRing ?? this.focusRing,
      navWidth: navWidth ?? this.navWidth,
      settingsCatWidth: settingsCatWidth ?? this.settingsCatWidth,
      fontFamily: fontFamily ?? this.fontFamily,
      monoFontFamily: monoFontFamily ?? this.monoFontFamily,
    );
  }

  @override
  FluentTokens lerp(ThemeExtension<FluentTokens>? other, double t) {
    if (other is! FluentTokens) return this;
    if (t < 0.5) return this;
    return other;
  }
}
