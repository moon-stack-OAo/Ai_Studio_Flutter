import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';

enum MaterialEmptyArt {
  noProvider,
  noMessages,
  noImages,
  noVideos,
  noSessions,
  noProviders,
}

/// Material 空态简易线稿（CustomPainter，跟随 token 亮暗；圆角/留白更松）。
class MaterialEmptyIllustration extends StatelessWidget {
  const MaterialEmptyIllustration({
    super.key,
    required this.art,
    this.size = 120,
  });

  const MaterialEmptyIllustration.noProvider({super.key, this.size = 128})
      : art = MaterialEmptyArt.noProvider;

  const MaterialEmptyIllustration.noMessages({super.key, this.size = 104})
      : art = MaterialEmptyArt.noMessages;

  const MaterialEmptyIllustration.noImages({super.key, this.size = 104})
      : art = MaterialEmptyArt.noImages;

  const MaterialEmptyIllustration.noVideos({super.key, this.size = 104})
      : art = MaterialEmptyArt.noVideos;

  const MaterialEmptyIllustration.noSessions({super.key, this.size = 88})
      : art = MaterialEmptyArt.noSessions;

  const MaterialEmptyIllustration.noProviders({super.key, this.size = 88})
      : art = MaterialEmptyArt.noProviders;

  final MaterialEmptyArt art;
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
            art: art,
            stroke: tokens.inkMuted,
            accent: tokens.primary,
            fill: tokens.surfaceMuted,
            soft: tokens.inkSecondary.withValues(alpha: 0.2),
          ),
        ),
      ),
    );
  }
}

class _MaterialEmptyPainter extends CustomPainter {
  const _MaterialEmptyPainter({
    required this.art,
    required this.stroke,
    required this.accent,
    required this.fill,
    required this.soft,
  });

  final MaterialEmptyArt art;
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

    final softFill = Paint()
      ..color = soft
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    switch (art) {
      case MaterialEmptyArt.noProvider:
        _paintNoProvider(
          canvas,
          strokePaint,
          accentStroke,
          fillPaint,
          accentFill,
        );
      case MaterialEmptyArt.noMessages:
        _paintNoMessages(canvas, strokePaint, accentStroke, fillPaint);
      case MaterialEmptyArt.noImages:
        _paintNoImages(canvas, strokePaint, accentStroke, fillPaint, softFill);
      case MaterialEmptyArt.noVideos:
        _paintNoVideos(
          canvas,
          strokePaint,
          accentStroke,
          fillPaint,
          accentFill,
        );
      case MaterialEmptyArt.noSessions:
        _paintNoSessions(canvas, strokePaint, accentStroke, fillPaint);
      case MaterialEmptyArt.noProviders:
        _paintNoProviders(
          canvas,
          strokePaint,
          accentStroke,
          fillPaint,
          accentFill,
        );
    }
    canvas.restore();
  }

  void _paintNoProvider(
    Canvas canvas,
    Paint strokePaint,
    Paint accentStroke,
    Paint fillPaint,
    Paint accentFill,
  ) {
    canvas.drawCircle(const Offset(48, 48), 28, fillPaint);
    canvas.drawCircle(const Offset(48, 48), 28, strokePaint);
    canvas.drawCircle(const Offset(48, 48), 10, accentFill);
    canvas.drawCircle(const Offset(48, 48), 10, accentStroke);
    canvas.drawLine(const Offset(48, 20), const Offset(48, 28), strokePaint);
    canvas.drawLine(const Offset(48, 68), const Offset(48, 76), strokePaint);
    canvas.drawLine(const Offset(20, 48), const Offset(28, 48), strokePaint);
    canvas.drawLine(const Offset(68, 48), const Offset(76, 48), strokePaint);
    canvas.drawLine(const Offset(28, 28), const Offset(34, 34), strokePaint);
    canvas.drawLine(const Offset(62, 62), const Offset(68, 68), strokePaint);
    canvas.drawLine(const Offset(68, 28), const Offset(62, 34), strokePaint);
    canvas.drawLine(const Offset(34, 62), const Offset(28, 68), strokePaint);
  }

  void _paintNoMessages(
    Canvas canvas,
    Paint strokePaint,
    Paint accentStroke,
    Paint fillPaint,
  ) {
    final bubble = RRect.fromRectAndRadius(
      const Rect.fromLTWH(16, 20, 48, 34),
      const Radius.circular(16),
    );
    canvas.drawRRect(bubble, fillPaint);
    canvas.drawRRect(bubble, strokePaint);
    final tail = Path()
      ..moveTo(28, 54)
      ..lineTo(24, 66)
      ..lineTo(40, 54);
    canvas.drawPath(tail, strokePaint);

    final reply = RRect.fromRectAndRadius(
      const Rect.fromLTWH(36, 48, 44, 28),
      const Radius.circular(14),
    );
    canvas.drawRRect(reply, accentStroke);
    canvas.drawLine(const Offset(46, 58), const Offset(66, 58), accentStroke);
    canvas.drawLine(const Offset(46, 64), const Offset(58, 64), accentStroke);
  }

  void _paintNoImages(
    Canvas canvas,
    Paint strokePaint,
    Paint accentStroke,
    Paint fillPaint,
    Paint softFill,
  ) {
    final frame = RRect.fromRectAndRadius(
      const Rect.fromLTWH(18, 20, 60, 56),
      const Radius.circular(12),
    );
    canvas.drawRRect(frame, fillPaint);
    canvas.drawRRect(frame, strokePaint);
    canvas.drawCircle(const Offset(36, 38), 5, accentStroke);
    final hills = Path()
      ..moveTo(18, 66)
      ..lineTo(34, 48)
      ..lineTo(48, 58)
      ..lineTo(62, 44)
      ..lineTo(78, 66)
      ..close();
    canvas.drawPath(hills, softFill);
    canvas.drawPath(
      Path()
        ..moveTo(18, 66)
        ..lineTo(34, 48)
        ..lineTo(48, 58)
        ..lineTo(62, 44)
        ..lineTo(78, 66),
      strokePaint,
    );
  }

  void _paintNoVideos(
    Canvas canvas,
    Paint strokePaint,
    Paint accentStroke,
    Paint fillPaint,
    Paint accentFill,
  ) {
    final frame = RRect.fromRectAndRadius(
      const Rect.fromLTWH(16, 26, 48, 44),
      const Radius.circular(10),
    );
    canvas.drawRRect(frame, fillPaint);
    canvas.drawRRect(frame, strokePaint);
    final play = Path()
      ..moveTo(64, 34)
      ..lineTo(80, 48)
      ..lineTo(64, 62)
      ..close();
    canvas.drawPath(play, accentFill);
    canvas.drawPath(play, accentStroke);
  }

  void _paintNoSessions(
    Canvas canvas,
    Paint strokePaint,
    Paint accentStroke,
    Paint fillPaint,
  ) {
    for (var i = 0; i < 3; i++) {
      final y = 22.0 + i * 20;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(18, y, 60, 16),
        const Radius.circular(8),
      );
      canvas.drawRRect(rect, fillPaint);
      canvas.drawRRect(rect, i == 0 ? accentStroke : strokePaint);
      canvas.drawCircle(
        Offset(30, y + 8),
        3,
        i == 0 ? accentStroke : strokePaint,
      );
      canvas.drawLine(
        Offset(40, y + 8),
        Offset(68, y + 8),
        i == 0 ? accentStroke : strokePaint,
      );
    }
  }

  void _paintNoProviders(
    Canvas canvas,
    Paint strokePaint,
    Paint accentStroke,
    Paint fillPaint,
    Paint accentFill,
  ) {
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
  }

  @override
  bool shouldRepaint(covariant _MaterialEmptyPainter oldDelegate) {
    return oldDelegate.art != art ||
        oldDelegate.stroke != stroke ||
        oldDelegate.accent != accent ||
        oldDelegate.fill != fill ||
        oldDelegate.soft != soft;
  }
}
