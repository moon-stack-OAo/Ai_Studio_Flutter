import 'package:flutter/material.dart' show VisualDensity;

/// UI 密度（SET-APPEARANCE）。Fluent / 桌面默认偏松（舒适）。
enum UiDensity {
  comfortable('舒适'),
  compact('紧凑');

  const UiDensity(this.label);

  final String label;

  String get wire => name;

  VisualDensity get visualDensity => switch (this) {
        UiDensity.comfortable => VisualDensity.standard,
        UiDensity.compact => VisualDensity.compact,
      };

  /// 会话列表项垂直内边距。
  double get sessionItemVerticalPadding => switch (this) {
        UiDensity.comfortable => 8,
        UiDensity.compact => 5,
      };

  /// 设置分类 / 会话窗格宽度。
  double get settingsCatWidth => switch (this) {
        UiDensity.comfortable => 260,
        UiDensity.compact => 232,
      };

  /// 由 [VisualDensity] 反推（主题已写入 visualDensity 时使用）。
  static UiDensity fromVisualDensity(VisualDensity density) {
    if (density.horizontal <= VisualDensity.compact.horizontal &&
        density.vertical <= VisualDensity.compact.vertical) {
      return UiDensity.compact;
    }
    return UiDensity.comfortable;
  }

  static UiDensity fromWire(String? value) {
    if (value == null || value.isEmpty) return UiDensity.comfortable;
    for (final item in UiDensity.values) {
      if (item.wire == value) return item;
    }
    return UiDensity.comfortable;
  }
}
