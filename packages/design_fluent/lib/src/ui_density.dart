import 'package:flutter/material.dart' show EdgeInsets, VisualDensity;

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

  /// 会话列表项间距。
  double get sessionListGap => switch (this) {
        UiDensity.comfortable => 4,
        UiDensity.compact => 2,
      };

  /// 设置分类 / 会话窗格宽度。
  double get settingsCatWidth => switch (this) {
        UiDensity.comfortable => 260,
        UiDensity.compact => 232,
      };

  /// Composer 外层内边距。
  EdgeInsets get composerPadding => switch (this) {
        UiDensity.comfortable =>
          const EdgeInsets.fromLTRB(20, 12, 20, 16),
        UiDensity.compact => const EdgeInsets.fromLTRB(16, 8, 16, 12),
      };

  /// Composer 输入卡片内边距。
  EdgeInsets get composerInnerPadding => switch (this) {
        UiDensity.comfortable =>
          const EdgeInsets.fromLTRB(14, 10, 10, 10),
        UiDensity.compact => const EdgeInsets.fromLTRB(10, 8, 8, 8),
      };

  /// 设置表单项垂直间距。
  double get settingsFormGap => switch (this) {
        UiDensity.comfortable => 12,
        UiDensity.compact => 8,
      };

  /// 设置分区卡片内边距。
  double get settingsSectionPadding => switch (this) {
        UiDensity.comfortable => 16,
        UiDensity.compact => 12,
      };

  /// 设置分类磁贴垂直内边距。
  double get settingsCatTileVertical => switch (this) {
        UiDensity.comfortable => 10,
        UiDensity.compact => 7,
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
