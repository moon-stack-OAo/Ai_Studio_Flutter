import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';

/// Material 空态简易线稿（CustomPainter，跟随 token 亮暗）。
///
/// 对话 / 生图 / 生视频 / 会话 / 提供商的空态已改为发丝线与状态点，
/// 目前只剩设置 · MCP 页还用这一枚。
class MaterialEmptyIllustration extends StatelessWidget {
  const MaterialEmptyIllustration.noProviders({super.key, this.size = 88});

  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    return Semantics(
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _MaterialEmptyPainter(
            stroke: tokens.inkMuted,
            accent: tokens.primary,
            fill: tokens.surfaceMuted,
          ),
        ),
      ),
    );
  }
}

class _MaterialEmptyPainter extends CustomPainter {
  const _MaterialEmptyPainter({
    required this.stroke,
    required this.accent,
    required this.fill,
  });

  final Color stroke;
  final Color accent;
  final Color fill;

  static const double _vb = 96;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / _vb;
    canvas.save();
    canvas.scale(s);

    final strokePaint = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final accentStroke = Paint()
      ..color = accent.withValues(alpha: 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final accentFill = Paint()
      ..color = accent.withValues(alpha: 0.14)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final fillPaint = Paint()
      ..color = fill
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final card = RRect.fromRectAndRadius(
      const Rect.fromLTWH(24, 20, 48, 56),
      const Radius.circular(14),
    );
    canvas.drawRRect(card, fillPaint);
    canvas.drawRRect(card, strokePaint);
    canvas.drawLine(const Offset(34, 36), const Offset(62, 36), strokePaint);
    canvas.drawLine(const Offset(34, 46), const Offset(54, 46), strokePaint);
    canvas.drawCircle(const Offset(48, 62), 6, accentFill);
    canvas.drawCircle(const Offset(48, 62), 6, accentStroke);
    final badge = RRect.fromRectAndRadius(
      const Rect.fromLTWH(64, 18, 18, 18),
      const Radius.circular(9),
    );
    canvas.drawRRect(badge, accentFill);
    canvas.drawRRect(badge, accentStroke);
    canvas.drawLine(const Offset(73, 23), const Offset(73, 31), accentStroke);
    canvas.drawLine(const Offset(69, 27), const Offset(77, 27), accentStroke);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MaterialEmptyPainter oldDelegate) {
    return oldDelegate.stroke != stroke ||
        oldDelegate.accent != accent ||
        oldDelegate.fill != fill;
  }
}
