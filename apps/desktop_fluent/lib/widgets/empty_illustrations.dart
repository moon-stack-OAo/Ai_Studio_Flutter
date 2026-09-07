import 'package:design_fluent/design_fluent.dart';
import 'package:flutter/widgets.dart';

enum FluentEmptyArt {
  noProvider,
  noMessages,
  noImages,
  noVideos,
  noSessions,
  noProviders,
}

/// Fluent 空态简易线稿（CustomPainter，跟随 token 亮暗）。
class FluentEmptyIllustration extends StatelessWidget {
  const FluentEmptyIllustration({
    super.key,
    required this.art,
    this.size = 112,
  });

  const FluentEmptyIllustration.noProvider({super.key, this.size = 120})
      : art = FluentEmptyArt.noProvider;

  const FluentEmptyIllustration.noMessages({super.key, this.size = 96})
      : art = FluentEmptyArt.noMessages;

  const FluentEmptyIllustration.noImages({super.key, this.size = 96})
      : art = FluentEmptyArt.noImages;

  const FluentEmptyIllustration.noVideos({super.key, this.size = 96})
      : art = FluentEmptyArt.noVideos;

  const FluentEmptyIllustration.noSessions({super.key, this.size = 72})
      : art = FluentEmptyArt.noSessions;

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
            soft: tokens.inkSecondary.withValues(alpha: 0.22),
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
    required this.soft,
  });

  final FluentEmptyArt art;
  final Color stroke;
  final Color accent;
  final Color fill;
  final Color soft;

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

    final softFill = Paint()
      ..color = soft
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    switch (art) {
      case FluentEmptyArt.noProvider:
        _paintNoProvider(canvas, strokePaint, accentStroke, fillPaint);
      case FluentEmptyArt.noMessages:
        _paintNoMessages(canvas, strokePaint, accentStroke, fillPaint);
      case FluentEmptyArt.noImages:
        _paintNoImages(canvas, strokePaint, accentStroke, fillPaint, softFill);
      case FluentEmptyArt.noVideos:
        _paintNoVideos(canvas, strokePaint, accentStroke, fillPaint);
      case FluentEmptyArt.noSessions:
        _paintNoSessions(canvas, strokePaint, accentStroke, fillPaint);
      case FluentEmptyArt.noProviders:
        _paintNoProviders(canvas, strokePaint, accentStroke, fillPaint);
    }
    canvas.restore();
  }

  void _paintNoProvider(
    Canvas canvas,
    Paint strokePaint,
    Paint accentStroke,
    Paint fillPaint,
  ) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(22, 28, 52, 40),
        const Radius.circular(6),
      ),
      fillPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(22, 28, 52, 40),
        const Radius.circular(6),
      ),
      strokePaint,
    );
    canvas.drawCircle(const Offset(38, 48), 5, accentStroke);
    canvas.drawLine(const Offset(43, 48), const Offset(58, 48), accentStroke);
    canvas.drawLine(const Offset(52, 48), const Offset(52, 42), accentStroke);
    canvas.drawLine(const Offset(56, 48), const Offset(56, 44), accentStroke);
    final spark = Path()
      ..moveTo(68, 22)
      ..lineTo(70, 28)
      ..lineTo(76, 30)
      ..lineTo(70, 32)
      ..lineTo(68, 38)
      ..lineTo(66, 32)
      ..lineTo(60, 30)
      ..lineTo(66, 28)
      ..close();
    canvas.drawPath(spark, accentStroke);
  }

  void _paintNoMessages(
    Canvas canvas,
    Paint strokePaint,
    Paint accentStroke,
    Paint fillPaint,
  ) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(18, 22, 42, 28),
        const Radius.circular(5),
      ),
      fillPaint,
    );
    final left = Path()
      ..moveTo(18, 22)
      ..lineTo(60, 22)
      ..lineTo(60, 44)
      ..lineTo(32, 44)
      ..lineTo(24, 52)
      ..lineTo(24, 44)
      ..lineTo(18, 44)
      ..close();
    canvas.drawPath(left, strokePaint);
    canvas.drawLine(const Offset(26, 32), const Offset(48, 32), strokePaint);
    canvas.drawLine(const Offset(26, 38), const Offset(40, 38), strokePaint);

    final right = Path()
      ..moveTo(40, 40)
      ..lineTo(78, 40)
      ..lineTo(78, 62)
      ..lineTo(72, 62)
      ..lineTo(72, 70)
      ..lineTo(64, 62)
      ..lineTo(40, 62)
      ..close();
    canvas.drawPath(right, accentStroke);
    canvas.drawLine(const Offset(48, 50), const Offset(70, 50), accentStroke);
  }

  void _paintNoImages(
    Canvas canvas,
    Paint strokePaint,
    Paint accentStroke,
    Paint fillPaint,
    Paint softFill,
  ) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(20, 22, 56, 52),
        const Radius.circular(4),
      ),
      fillPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(20, 22, 56, 52),
        const Radius.circular(4),
      ),
      strokePaint,
    );
    canvas.drawCircle(const Offset(34, 36), 4, accentStroke);
    final mountain = Path()
      ..moveTo(20, 64)
      ..lineTo(36, 46)
      ..lineTo(48, 56)
      ..lineTo(60, 42)
      ..lineTo(76, 64)
      ..close();
    canvas.drawPath(mountain, softFill);
    canvas.drawPath(
      Path()
        ..moveTo(20, 64)
        ..lineTo(36, 46)
        ..lineTo(48, 56)
        ..lineTo(60, 42)
        ..lineTo(76, 64),
      strokePaint,
    );
  }

  void _paintNoVideos(
    Canvas canvas,
    Paint strokePaint,
    Paint accentStroke,
    Paint fillPaint,
  ) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(18, 28, 44, 40),
        const Radius.circular(4),
      ),
      fillPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(18, 28, 44, 40),
        const Radius.circular(4),
      ),
      strokePaint,
    );
    final play = Path()
      ..moveTo(62, 34)
      ..lineTo(78, 48)
      ..lineTo(62, 62)
      ..close();
    canvas.drawPath(play, accentStroke);
  }

  void _paintNoSessions(
    Canvas canvas,
    Paint strokePaint,
    Paint accentStroke,
    Paint fillPaint,
  ) {
    for (var i = 0; i < 3; i++) {
      final y = 26.0 + i * 18;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(22, y, 52, 14),
        const Radius.circular(3),
      );
      canvas.drawRRect(rect, fillPaint);
      canvas.drawRRect(rect, i == 1 ? accentStroke : strokePaint);
      canvas.drawCircle(
        Offset(30, y + 7),
        2.5,
        i == 1 ? accentStroke : strokePaint,
      );
      canvas.drawLine(
        Offset(38, y + 7),
        Offset(64, y + 7),
        i == 1 ? accentStroke : strokePaint,
      );
    }
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
        oldDelegate.fill != fill ||
        oldDelegate.soft != soft;
  }
}
