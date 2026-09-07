/// 字号五档（SET-APPEARANCE）。
enum AppFontScale {
  smaller(0.85, '更小'),
  small(0.92, '较小'),
  standard(1.0, '标准'),
  large(1.08, '较大'),
  larger(1.15, '更大');

  const AppFontScale(this.factor, this.label);

  final double factor;
  final String label;

  String get wire => name;

  static AppFontScale fromWire(String? value) {
    if (value == null || value.isEmpty) return AppFontScale.standard;
    for (final item in AppFontScale.values) {
      if (item.wire == value) return item;
    }
    return AppFontScale.standard;
  }
}
