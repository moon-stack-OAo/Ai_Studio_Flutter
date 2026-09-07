import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/material.dart' show Brightness, Color, ThemeExtension;

/// Material 设计 token（亮色 Claude 向 / 暗色 Cursor 向）。
@immutable
class MaterialTokens extends ThemeExtension<MaterialTokens> {
  const MaterialTokens({
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
    required this.scrim,
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
  final Color scrim;
  final String fontFamily;
  final String monoFontFamily;

  static const String fontStackFamily = 'Roboto';
  static const String monoStackFamily = 'Roboto Mono';

  /// Light — Claude 向
  static const MaterialTokens light = MaterialTokens(
    brightness: Brightness.light,
    canvas: Color(0xFFFAF9F5),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFEFEEEB),
    surfaceElevated: Color(0xFFEFE9DE),
    ink: Color(0xFF141413),
    inkSecondary: Color(0xFF3D3D3A),
    inkMuted: Color(0xFF5C5A55),
    border: Color(0xFFE7E6E1),
    primary: Color(0xFFD97757),
    primaryPressed: Color(0xFFA9583E),
    onPrimary: Color(0xFFFFFFFF),
    success: Color(0xFF2F6A40),
    danger: Color(0xFFB42318),
    warning: Color(0xFFB45309),
    focusRing: Color(0x99D97757),
    scrim: Color(0xB8141413),
    fontFamily: fontStackFamily,
    monoFontFamily: monoStackFamily,
  );

  /// Dark — Cursor 向（primary 为冷蓝，与亮色暖珊瑚不共用 hue）
  static const MaterialTokens dark = MaterialTokens(
    brightness: Brightness.dark,
    canvas: Color(0xFF0A0A0A),
    surface: Color(0xFF141414),
    surfaceMuted: Color(0xFF18181B),
    surfaceElevated: Color(0xFF1C1C1C),
    ink: Color(0xFFFAFAFA),
    inkSecondary: Color(0xFFA1A1AA),
    inkMuted: Color(0xFF8B8B96),
    border: Color(0xFF27272A),
    primary: Color(0xFF3B82F6),
    primaryPressed: Color(0xFF2563EB),
    onPrimary: Color(0xFFFFFFFF),
    success: Color(0xFF34D399),
    danger: Color(0xFFEF4444),
    warning: Color(0xFFF59E0B),
    focusRing: Color(0x993B82F6),
    scrim: Color(0xCC000000),
    fontFamily: fontStackFamily,
    monoFontFamily: monoStackFamily,
  );

  static MaterialTokens ofBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  @override
  MaterialTokens copyWith({
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
    Color? scrim,
    String? fontFamily,
    String? monoFontFamily,
  }) {
    return MaterialTokens(
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
      scrim: scrim ?? this.scrim,
      fontFamily: fontFamily ?? this.fontFamily,
      monoFontFamily: monoFontFamily ?? this.monoFontFamily,
    );
  }

  @override
  MaterialTokens lerp(ThemeExtension<MaterialTokens>? other, double t) {
    if (other is! MaterialTokens) return this;
    if (t < 0.5) return this;
    return other;
  }
}
