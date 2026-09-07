import 'package:flutter/material.dart';

import 'font_scale.dart';
import 'tokens.dart';
import 'ui_density.dart';

/// Material 正文字体栈（系统字体，不内嵌商业字库）。
/// Roboto → Noto Sans SC → 系统回退。
const List<String> kMaterialFontFamilyFallback = [
  'Noto Sans SC',
  'system-ui',
  '-apple-system',
  'PingFang SC',
  'Microsoft YaHei',
  'sans-serif',
];

/// Material 等宽字体回退（代码块 / 日志）。
/// Roboto Mono → Noto Sans Mono → 系统等宽。
const List<String> kMaterialMonoFontFamilyFallback = [
  'Noto Sans Mono',
  'SF Mono',
  'Consolas',
  'monospace',
];

/// 给 [TextStyle] 挂上 Material 等宽主族与回退栈。
extension MaterialMonoTextStyle on TextStyle {
  TextStyle withMonoFont(MaterialTokens tokens) => copyWith(
        fontFamily: tokens.monoFontFamily,
        fontFamilyFallback: kMaterialMonoFontFamilyFallback,
      );
}

TextStyle _scaleStyle(
  TextStyle? style, {
  required double factor,
  required Color color,
  required double fallbackSize,
}) {
  final size = (style?.fontSize ?? fallbackSize) * factor;
  return (style ?? const TextStyle()).copyWith(
    color: color,
    fontFamily: MaterialTokens.fontStackFamily,
    fontFamilyFallback: kMaterialFontFamilyFallback,
    fontSize: size,
  );
}

TextTheme _textTheme(MaterialTokens tokens, double fontSizeFactor) {
  final typography = Typography.material2021(platform: TargetPlatform.android);
  final base = tokens.brightness == Brightness.dark
      ? typography.white
      : typography.black;
  final ink = tokens.ink;
  return TextTheme(
    displayLarge: _scaleStyle(
      base.displayLarge,
      factor: fontSizeFactor,
      color: ink,
      fallbackSize: 57,
    ),
    displayMedium: _scaleStyle(
      base.displayMedium,
      factor: fontSizeFactor,
      color: ink,
      fallbackSize: 45,
    ),
    displaySmall: _scaleStyle(
      base.displaySmall,
      factor: fontSizeFactor,
      color: ink,
      fallbackSize: 36,
    ),
    headlineLarge: _scaleStyle(
      base.headlineLarge,
      factor: fontSizeFactor,
      color: ink,
      fallbackSize: 32,
    ),
    headlineMedium: _scaleStyle(
      base.headlineMedium,
      factor: fontSizeFactor,
      color: ink,
      fallbackSize: 28,
    ),
    headlineSmall: _scaleStyle(
      base.headlineSmall,
      factor: fontSizeFactor,
      color: ink,
      fallbackSize: 24,
    ),
    titleLarge: _scaleStyle(
      base.titleLarge,
      factor: fontSizeFactor,
      color: ink,
      fallbackSize: 22,
    ),
    titleMedium: _scaleStyle(
      base.titleMedium,
      factor: fontSizeFactor,
      color: ink,
      fallbackSize: 16,
    ),
    titleSmall: _scaleStyle(
      base.titleSmall,
      factor: fontSizeFactor,
      color: ink,
      fallbackSize: 14,
    ),
    bodyLarge: _scaleStyle(
      base.bodyLarge,
      factor: fontSizeFactor,
      color: ink,
      fallbackSize: 16,
    ),
    bodyMedium: _scaleStyle(
      base.bodyMedium,
      factor: fontSizeFactor,
      color: ink,
      fallbackSize: 14,
    ),
    bodySmall: _scaleStyle(
      base.bodySmall,
      factor: fontSizeFactor,
      color: tokens.inkSecondary,
      fallbackSize: 12,
    ),
    labelLarge: _scaleStyle(
      base.labelLarge,
      factor: fontSizeFactor,
      color: ink,
      fallbackSize: 14,
    ),
    labelMedium: _scaleStyle(
      base.labelMedium,
      factor: fontSizeFactor,
      color: ink,
      fallbackSize: 12,
    ),
    labelSmall: _scaleStyle(
      base.labelSmall,
      factor: fontSizeFactor,
      color: tokens.inkMuted,
      fallbackSize: 11,
    ),
  );
}

ColorScheme _colorScheme(MaterialTokens tokens) {
  return ColorScheme(
    brightness: tokens.brightness,
    primary: tokens.primary,
    onPrimary: tokens.onPrimary,
    primaryContainer: tokens.surfaceElevated,
    onPrimaryContainer: tokens.ink,
    secondary: tokens.inkSecondary,
    onSecondary: tokens.onPrimary,
    secondaryContainer: tokens.surfaceMuted,
    onSecondaryContainer: tokens.ink,
    tertiary: tokens.primaryPressed,
    onTertiary: tokens.onPrimary,
    error: tokens.danger,
    onError: tokens.onPrimary,
    surface: tokens.surface,
    onSurface: tokens.ink,
    onSurfaceVariant: tokens.inkSecondary,
    outline: tokens.border,
    outlineVariant: tokens.border,
    shadow: const Color(0xFF000000),
    scrim: const Color(0xFF000000),
    inverseSurface: tokens.ink,
    onInverseSurface: tokens.canvas,
    inversePrimary: tokens.primaryPressed,
    surfaceTint: tokens.primary,
  );
}

ThemeData _buildTheme(
  MaterialTokens tokens, {
  AppFontScale fontScale = AppFontScale.standard,
  UiDensity density = UiDensity.compact,
}) {
  final factor = fontScale.factor;
  final scheme = _colorScheme(tokens);
  return ThemeData(
    useMaterial3: true,
    brightness: tokens.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: tokens.canvas,
    canvasColor: tokens.canvas,
    cardColor: tokens.surface,
    dividerColor: tokens.border,
    visualDensity: density.visualDensity,
    fontFamily: tokens.fontFamily,
    fontFamilyFallback: kMaterialFontFamilyFallback,
    textTheme: _textTheme(tokens, factor),
    primaryTextTheme: _textTheme(tokens, factor),
    appBarTheme: AppBarTheme(
      backgroundColor: tokens.surface,
      foregroundColor: tokens.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: tokens.ink,
        fontWeight: FontWeight.w600,
        fontSize: 16 * factor,
        fontFamily: tokens.fontFamily,
        fontFamilyFallback: kMaterialFontFamilyFallback,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: tokens.surface,
      indicatorColor: tokens.primary.withValues(alpha: 0.18),
      elevation: 0,
      height: density.navigationBarHeight,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 11 * factor,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected ? tokens.primaryPressed : tokens.inkMuted,
          fontFamily: tokens.fontFamily,
          fontFamilyFallback: kMaterialFontFamilyFallback,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 22,
          color: selected ? tokens.primaryPressed : tokens.inkMuted,
        );
      }),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: tokens.primary,
        foregroundColor: tokens.onPrimary,
        disabledBackgroundColor: tokens.surfaceMuted,
        disabledForegroundColor: tokens.inkMuted,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: tokens.ink,
        side: BorderSide(color: tokens.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tokens.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: tokens.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: tokens.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: tokens.primary, width: 1.5),
      ),
      hintStyle: TextStyle(color: tokens.inkMuted),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: tokens.surfaceElevated,
      contentTextStyle: TextStyle(color: tokens.ink),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: tokens.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: tokens.border),
      ),
      titleTextStyle: TextStyle(
        color: tokens.ink,
        fontWeight: FontWeight.w600,
        fontSize: 18 * factor,
        fontFamily: tokens.fontFamily,
        fontFamilyFallback: kMaterialFontFamilyFallback,
      ),
      contentTextStyle: TextStyle(
        color: tokens.inkSecondary,
        fontSize: 14 * factor,
        height: 1.45,
        fontFamily: tokens.fontFamily,
        fontFamilyFallback: kMaterialFontFamilyFallback,
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: tokens.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 2,
      showDragHandle: true,
      dragHandleColor: tokens.inkMuted.withValues(alpha: 0.45),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    extensions: [tokens],
  );
}

/// 亮色 Material ThemeData（Claude 向暖奶油 + 暖珊瑚 primary）。
ThemeData buildMaterialLightTheme({
  AppFontScale fontScale = AppFontScale.standard,
  UiDensity density = UiDensity.compact,
}) =>
    _buildTheme(
      MaterialTokens.light,
      fontScale: fontScale,
      density: density,
    );

/// 暗色 Material ThemeData（Cursor 向近黑 + 冷蓝 primary）。
ThemeData buildMaterialDarkTheme({
  AppFontScale fontScale = AppFontScale.standard,
  UiDensity density = UiDensity.compact,
}) =>
    _buildTheme(
      MaterialTokens.dark,
      fontScale: fontScale,
      density: density,
    );

/// 从 [Theme] 读取本包 token；若缺失则按亮度回退。
MaterialTokens materialTokensOf(BuildContext context) {
  final theme = Theme.of(context);
  final ext = theme.extension<MaterialTokens>();
  return ext ?? MaterialTokens.ofBrightness(theme.brightness);
}
