import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;

/// 外观设置（SET-APPEARANCE）：主题 / 字号 / 密度；兼存关闭行为（SET-CLOSE-BEHAVIOR）。
/// wire 字符串，不依赖 design_* UI 包。
class AppearanceSettings {
  const AppearanceSettings({
    this.themePreference = defaultThemePreference,
    this.fontScale = defaultFontScale,
    this.density = defaultDensity,
    this.closeBehavior = defaultCloseBehavior,
  });

  /// 桌面舒适、移动紧凑；非法 / 缺失 wire 时的回退亦走此逻辑。
  static AppearanceSettings get recommended => AppearanceSettings(
        density: platformDefaultDensity(),
      );

  static const defaultThemePreference = 'light';
  static const defaultFontScale = 'standard';

  /// 非法 wire 的静态回退；首装推荐值请用 [platformDefaultDensity] / [recommended]。
  static const defaultDensity = 'comfortable';
  static const defaultDensityMobile = 'compact';
  static const defaultCloseBehavior = 'ask';

  static const themePreferenceValues = {'light', 'dark'};
  static const fontScaleValues = {
    'smaller',
    'small',
    'standard',
    'large',
    'larger',
  };
  static const densityValues = {'comfortable', 'compact'};
  static const closeBehaviorValues = {'ask', 'quit', 'tray'};

  /// 桌面（含桌面 Web）→ comfortable；移动 → compact。
  static String platformDefaultDensity({TargetPlatform? platform}) {
    final p = platform ?? defaultTargetPlatform;
    return switch (p) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia =>
        defaultDensityMobile,
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows =>
        defaultDensity,
    };
  }

  /// `light` | `dark`
  final String themePreference;

  /// `smaller` | `small` | `standard` | `large` | `larger`
  final String fontScale;

  /// `comfortable` | `compact`
  final String density;

  /// `ask` | `quit` | `tray`（仅桌面；关闭时由 WindowCloseCoordinator 拦截）
  final String closeBehavior;

  AppearanceSettings copyWith({
    String? themePreference,
    String? fontScale,
    String? density,
    String? closeBehavior,
  }) {
    return AppearanceSettings(
      themePreference: themePreference ?? this.themePreference,
      fontScale: fontScale ?? this.fontScale,
      density: density ?? this.density,
      closeBehavior: closeBehavior ?? this.closeBehavior,
    );
  }

  AppearanceSettings sanitized() {
    final theme = themePreferenceValues.contains(themePreference)
        ? themePreference
        : defaultThemePreference;
    final scale =
        fontScaleValues.contains(fontScale) ? fontScale : defaultFontScale;
    final dens = densityValues.contains(density)
        ? density
        : platformDefaultDensity();
    final close = closeBehaviorValues.contains(closeBehavior)
        ? closeBehavior
        : defaultCloseBehavior;
    return AppearanceSettings(
      themePreference: theme,
      fontScale: scale,
      density: dens,
      closeBehavior: close,
    );
  }

  Map<String, dynamic> toJson() => {
        'themePreference': themePreference,
        'fontScale': fontScale,
        'density': density,
        'closeBehavior': closeBehavior,
      };

  factory AppearanceSettings.fromJson(Map<String, dynamic> json) {
    return AppearanceSettings(
      themePreference:
          json['themePreference']?.toString() ?? defaultThemePreference,
      fontScale: json['fontScale']?.toString() ?? defaultFontScale,
      density: json['density']?.toString() ?? platformDefaultDensity(),
      closeBehavior:
          json['closeBehavior']?.toString() ?? defaultCloseBehavior,
    ).sanitized();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppearanceSettings &&
          themePreference == other.themePreference &&
          fontScale == other.fontScale &&
          density == other.density &&
          closeBehavior == other.closeBehavior;

  @override
  int get hashCode =>
      Object.hash(themePreference, fontScale, density, closeBehavior);
}
