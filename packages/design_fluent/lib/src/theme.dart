import 'package:fluent_ui/fluent_ui.dart';

import 'font_scale.dart';
import 'tokens.dart';
import 'ui_density.dart';

/// Fluent 正文字体回退（系统字体，不内嵌商业字库）。
/// Segoe UI Variable 为主族；其后 Segoe UI → 系统 / CJK。
const List<String> kFluentFontFamilyFallback = [
  'Segoe UI',
  'system-ui',
  '-apple-system',
  'BlinkMacSystemFont',
  'PingFang SC',
  'Microsoft YaHei',
  'sans-serif',
];

/// Fluent 等宽字体回退（代码块 / 日志）。
const List<String> kFluentMonoFontFamilyFallback = [
  'Cascadia Mono',
  'SF Mono',
  'Consolas',
  'Microsoft YaHei Mono',
  'monospace',
];

/// 给 [TextStyle] 挂上 Fluent 等宽主族与回退栈。
extension FluentMonoTextStyle on TextStyle {
  TextStyle withMonoFont(FluentTokens tokens) => copyWith(
        fontFamily: tokens.monoFontFamily,
        fontFamilyFallback: kFluentMonoFontFamilyFallback,
      );
}

AccentColor _accentFrom(Color primary, Color pressed) {
  return AccentColor.swatch({
    'darkest': Color.lerp(pressed, const Color(0xFF000000), 0.35)!,
    'darker': Color.lerp(pressed, const Color(0xFF000000), 0.18)!,
    'dark': pressed,
    'normal': primary,
    'light': Color.lerp(primary, const Color(0xFFFFFFFF), 0.18)!,
    'lighter': Color.lerp(primary, const Color(0xFFFFFFFF), 0.32)!,
    'lightest': Color.lerp(primary, const Color(0xFFFFFFFF), 0.48)!,
  });
}

TextStyle? _applyFluentFont(TextStyle? style, FluentTokens tokens) {
  if (style == null) return null;
  return style.copyWith(
    fontFamily: tokens.fontFamily,
    fontFamilyFallback: kFluentFontFamilyFallback,
  );
}

Typography _typography(FluentTokens tokens, double fontSizeFactor) {
  final base = Typography.fromBrightness(
    brightness: tokens.brightness,
    color: tokens.ink,
  ).apply(fontSizeFactor: fontSizeFactor);
  return Typography.raw(
    display: _applyFluentFont(base.display, tokens),
    titleLarge: _applyFluentFont(base.titleLarge, tokens),
    title: _applyFluentFont(base.title, tokens),
    subtitle: _applyFluentFont(base.subtitle, tokens),
    bodyLarge: _applyFluentFont(base.bodyLarge, tokens),
    bodyStrong: _applyFluentFont(base.bodyStrong, tokens),
    body: _applyFluentFont(base.body, tokens),
    caption: _applyFluentFont(base.caption, tokens),
  );
}

NavigationPaneThemeData _navPaneTheme(
  FluentTokens tokens,
  double fontSizeFactor,
) {
  return NavigationPaneThemeData(
    backgroundColor: tokens.surfaceMuted,
    overlayBackgroundColor: tokens.surface,
    highlightColor: tokens.primary,
    selectedIconColor: WidgetStatePropertyAll(tokens.primaryPressed),
    unselectedIconColor: WidgetStatePropertyAll(tokens.inkSecondary),
    selectedTextStyle: WidgetStatePropertyAll(
      TextStyle(
        color: tokens.ink,
        fontWeight: FontWeight.w600,
        fontFamily: tokens.fontFamily,
        fontFamilyFallback: kFluentFontFamilyFallback,
        fontSize: 14 * fontSizeFactor,
      ),
    ),
    unselectedTextStyle: WidgetStatePropertyAll(
      TextStyle(
        color: tokens.inkSecondary,
        fontFamily: tokens.fontFamily,
        fontFamilyFallback: kFluentFontFamilyFallback,
        fontSize: 14 * fontSizeFactor,
      ),
    ),
  );
}

FluentThemeData _buildTheme(
  FluentTokens tokens, {
  AppFontScale fontScale = AppFontScale.standard,
  UiDensity density = UiDensity.comfortable,
}) {
  final accent = _accentFrom(tokens.primary, tokens.primaryPressed);
  final factor = fontScale.factor;
  final densityTokens = density.settingsCatWidth == tokens.settingsCatWidth
      ? tokens
      : tokens.copyWith(settingsCatWidth: density.settingsCatWidth);
  return FluentThemeData(
    brightness: tokens.brightness,
    accentColor: accent,
    scaffoldBackgroundColor: tokens.canvas,
    micaBackgroundColor: tokens.canvas,
    acrylicBackgroundColor: tokens.surface,
    cardColor: tokens.surface,
    menuColor: tokens.surfaceElevated,
    shadowColor: tokens.brightness == Brightness.dark
        ? const Color(0xCC000000)
        : const Color(0x33000000),
    inactiveColor: tokens.inkSecondary,
    inactiveBackgroundColor: tokens.surfaceMuted,
    activeColor: tokens.onPrimary,
    selectionColor: tokens.primary.withValues(alpha: 0.28),
    typography: _typography(tokens, factor),
    visualDensity: density.visualDensity,
    navigationPaneTheme: _navPaneTheme(tokens, factor),
    focusTheme: FocusThemeData(
      glowFactor: 0,
      primaryBorder: BorderSide(color: tokens.primary, width: 2),
      secondaryBorder: BorderSide(color: tokens.focusRing, width: 1),
    ),
    dialogTheme: buildFluentContentDialogTheme(tokens),
    extensions: [densityTokens],
  );
}

/// 与会话参数 Dialog 对齐的 ContentDialog 装饰（全局 dialogTheme）。
ContentDialogThemeData buildFluentContentDialogTheme(FluentTokens tokens) {
  final border = Color.lerp(tokens.border, tokens.ink, 0.15)!;
  return ContentDialogThemeData(
    decoration: BoxDecoration(
      color: tokens.surfaceElevated,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: border),
      boxShadow: kElevationToShadow[6],
    ),
    padding: const EdgeInsetsDirectional.all(20),
    titlePadding: const EdgeInsetsDirectional.only(bottom: 12),
    actionsSpacing: 10,
    actionsDecoration: BoxDecoration(
      color: tokens.surfaceMuted,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
    ),
    actionsPadding: const EdgeInsetsDirectional.all(20),
    titleStyle: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: tokens.ink,
      fontFamily: tokens.fontFamily,
      fontFamilyFallback: kFluentFontFamilyFallback,
    ),
    bodyStyle: TextStyle(
      fontSize: 13,
      height: 1.45,
      color: tokens.inkSecondary,
      fontFamily: tokens.fontFamily,
      fontFamilyFallback: kFluentFontFamilyFallback,
    ),
  );
}

/// 亮色 FluentThemeData（Claude 向暖奶油 + 暖珊瑚 primary）。
FluentThemeData buildFluentLightTheme({
  AppFontScale fontScale = AppFontScale.standard,
  UiDensity density = UiDensity.comfortable,
}) =>
    _buildTheme(
      FluentTokens.light,
      fontScale: fontScale,
      density: density,
    );

/// 暗色 FluentThemeData（Cursor 向近黑 + 冷蓝 primary）。
FluentThemeData buildFluentDarkTheme({
  AppFontScale fontScale = AppFontScale.standard,
  UiDensity density = UiDensity.comfortable,
}) =>
    _buildTheme(
      FluentTokens.dark,
      fontScale: fontScale,
      density: density,
    );

/// 从 [FluentTheme] 读取本包 token；若缺失则按亮度回退。
FluentTokens fluentTokensOf(BuildContext context) {
  final theme = FluentTheme.of(context);
  final ext = theme.extension<FluentTokens>();
  return ext ?? FluentTokens.ofBrightness(theme.brightness);
}
