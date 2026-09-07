import 'package:flutter/material.dart' show VisualDensity;

/// UI 密度（SET-APPEARANCE）。Material / 移动端默认偏紧（紧凑），仍保留两档。
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

  /// 会话列表项垂直内边距（紧凑仍兼顾触控）。
  double get sessionItemVerticalPadding => switch (this) {
        UiDensity.comfortable => 14,
        UiDensity.compact => 10,
      };

  /// 会话列表分隔间距。
  double get sessionListSeparator => switch (this) {
        UiDensity.comfortable => 8,
        UiDensity.compact => 6,
      };

  /// 底栏 NavigationBar 高度；紧凑 64、舒适略松，均 ≥ 触控主操作约 48dp。
  double get navigationBarHeight => switch (this) {
        UiDensity.comfortable => 68,
        UiDensity.compact => 64,
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
    if (value == null || value.isEmpty) return UiDensity.compact;
    for (final item in UiDensity.values) {
      if (item.wire == value) return item;
    }
    return UiDensity.compact;
  }
}
