import 'package:flutter/widgets.dart';

/// 主导航四入口（对齐 OpenDesign 线框 SVG）。
enum NavIconKind {
  chat,
  image,
  video,
  settings,
}

/// Material 底栏导航图标工厂（默认 22×22，stroke≈1.8）。
abstract final class NavIcons {
  static Widget chat({
    Key? key,
    double size = 22,
    bool selected = false,
    Color? color,
  }) =>
      AppNavIcon(
        key: key,
        kind: NavIconKind.chat,
        size: size,
        selected: selected,
        color: color,
      );

  static Widget image({
    Key? key,
    double size = 22,
    bool selected = false,
    Color? color,
  }) =>
      AppNavIcon(
        key: key,
        kind: NavIconKind.image,
        size: size,
        selected: selected,
        color: color,
      );

  static Widget video({
    Key? key,
    double size = 22,
    bool selected = false,
    Color? color,
  }) =>
      AppNavIcon(
        key: key,
        kind: NavIconKind.video,
        size: size,
        selected: selected,
        color: color,
      );

  static Widget settings({
    Key? key,
    double size = 22,
    bool selected = false,
    Color? color,
  }) =>
      AppNavIcon(
        key: key,
        kind: NavIconKind.settings,
        size: size,
        selected: selected,
        color: color,
      );

  static Widget forKind(
    NavIconKind kind, {
    Key? key,
    double size = 22,
    bool selected = false,
    Color? color,
  }) =>
      AppNavIcon(
        key: key,
        kind: kind,
        size: size,
        selected: selected,
        color: color,
      );
}

/// 自定义线框图标：颜色跟随 [IconTheme] / [color]，选中略加粗描边。
class AppNavIcon extends StatelessWidget {
  const AppNavIcon({
    super.key,
    required this.kind,
    this.size = 22,
    this.selected = false,
    this.color,
    this.strokeWidth,
  });

  final NavIconKind kind;
  final double size;
  final bool selected;
  final Color? color;

  /// 未选中基准描边；默认按显示尺寸贴近 OD（≤18 → 1.7，否则 1.8）。
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final effectiveColor = color ??
        iconTheme.color ??
        DefaultTextStyle.of(context).style.color ??
        const Color(0xFF000000);
    final base = strokeWidth ?? (size <= 18 ? 1.7 : 1.8);
    final effectiveStroke = selected ? base + 0.4 : base;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _NavIconPainter(
          kind: kind,
          color: effectiveColor,
          strokeWidth: effectiveStroke,
        ),
      ),
    );
  }
}

class _NavIconPainter extends CustomPainter {
  const _NavIconPainter({
    required this.kind,
    required this.color,
    required this.strokeWidth,
  });

  final NavIconKind kind;
  final Color color;
  final double strokeWidth;

  static const double _viewBox = 24;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _viewBox;
    canvas.save();
    canvas.scale(scale);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth / scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    switch (kind) {
      case NavIconKind.chat:
        _paintChat(canvas, paint);
      case NavIconKind.image:
        _paintImage(canvas, paint);
      case NavIconKind.video:
        _paintVideo(canvas, paint);
      case NavIconKind.settings:
        _paintSettings(canvas, paint);
    }
    canvas.restore();
  }

  /// OD: `<path d="M4 6h16v10H8l-4 3V6z"/>`
  void _paintChat(Canvas canvas, Paint paint) {
    final path = Path()
      ..moveTo(4, 6)
      ..lineTo(20, 6)
      ..lineTo(20, 16)
      ..lineTo(8, 16)
      ..lineTo(4, 19)
      ..lineTo(4, 6)
      ..close();
    canvas.drawPath(path, paint);
  }

  /// OD: rect + circle + mountain path
  void _paintImage(Canvas canvas, Paint paint) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(4, 5, 16, 14),
        const Radius.circular(2),
      ),
      paint,
    );
    canvas.drawCircle(const Offset(9, 10), 1.5, paint);
    final mountain = Path()
      ..moveTo(4, 16)
      ..lineTo(9, 12)
      ..lineTo(13, 15)
      ..lineTo(16, 13)
      ..lineTo(20, 16);
    canvas.drawPath(mountain, paint);
  }

  /// OD: rect + play chevron
  void _paintVideo(Canvas canvas, Paint paint) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(3, 6, 13, 12),
        const Radius.circular(2),
      ),
      paint,
    );
    final chevron = Path()
      ..moveTo(16, 10)
      ..lineTo(21, 7)
      ..lineTo(21, 17)
      ..lineTo(16, 14)
      ..close();
    canvas.drawPath(chevron, paint);
  }

  /// OD: 中心圆 + 八向放射刻度（非齿轮）
  void _paintSettings(Canvas canvas, Paint paint) {
    canvas.drawCircle(const Offset(12, 12), 3, paint);
    final ticks = Path()
      ..moveTo(12, 3)
      ..lineTo(12, 5)
      ..moveTo(12, 19)
      ..lineTo(12, 21)
      ..moveTo(4.9, 4.9)
      ..lineTo(6.3, 6.3)
      ..moveTo(17.7, 17.7)
      ..lineTo(19.1, 19.1)
      ..moveTo(3, 12)
      ..lineTo(5, 12)
      ..moveTo(19, 12)
      ..lineTo(21, 12)
      ..moveTo(4.9, 19.1)
      ..lineTo(6.3, 17.7)
      ..moveTo(17.7, 6.3)
      ..lineTo(19.1, 4.9);
    canvas.drawPath(ticks, paint);
  }

  @override
  bool shouldRepaint(covariant _NavIconPainter oldDelegate) {
    return oldDelegate.kind != kind ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
