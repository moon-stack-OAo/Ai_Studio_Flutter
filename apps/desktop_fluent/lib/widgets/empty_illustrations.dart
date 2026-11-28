import 'package:design_fluent/design_fluent.dart';
import 'package:flutter/widgets.dart';

enum FluentEmptyArt { noProviders }

/// Fluent 空态简易线稿（CustomPainter，跟随 token 亮暗）。
class FluentEmptyIllustration extends StatelessWidget {
  const FluentEmptyIllustration({
    super.key,
    required this.art,
    this.size = 112,
  });

  const FluentEmptyIllustration.noProviders({super.key, this.size = 72})
      : art = FluentEmptyArt.noProviders;

  final FluentEmptyArt art;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    return Semantics(
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _FluentEmptyPainter(
            art: art,
            stroke: tokens.inkMuted,
            accent: tokens.primary,
            fill: tokens.surfaceMuted,
          ),
        ),
      ),
    );
  }
}

class _FluentEmptyPainter extends CustomPainter {
  const _FluentEmptyPainter({
    required this.art,
    required this.stroke,
    required this.accent,
    required this.fill,
  });

  final FluentEmptyArt art;
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
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final accentStroke = Paint()
      ..color = accent.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final fillPaint = Paint()
      ..color = fill
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    switch (art) {
      case FluentEmptyArt.noProviders:
        _paintNoProviders(canvas, strokePaint, accentStroke, fillPaint);
    }
    canvas.restore();
  }

  void _paintNoProviders(
    Canvas canvas,
    Paint strokePaint,
    Paint accentStroke,
    Paint fillPaint,
  ) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(28, 24, 40, 48),
        const Radius.circular(5),
      ),
      fillPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(28, 24, 40, 48),
        const Radius.circular(5),
      ),
      strokePaint,
    );
    canvas.drawLine(const Offset(36, 36), const Offset(60, 36), strokePaint);
    canvas.drawLine(const Offset(36, 46), const Offset(54, 46), strokePaint);
    canvas.drawCircle(const Offset(48, 60), 5, accentStroke);
    final plus = Path()
      ..moveTo(70, 28)
      ..lineTo(70, 40)
      ..moveTo(64, 34)
      ..lineTo(76, 34);
    canvas.drawPath(plus, accentStroke);
  }

  @override
  bool shouldRepaint(covariant _FluentEmptyPainter oldDelegate) {
    return oldDelegate.art != art ||
        oldDelegate.stroke != stroke ||
        oldDelegate.accent != accent ||
        oldDelegate.fill != fill;
  }
}
