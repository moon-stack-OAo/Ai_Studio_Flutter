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
    // OD Material: looser radius card + two lines + badge plus.
    final card = RRect.fromRectAndRadius(
      const Rect.fromLTWH(20, 24, 56, 48),
      const Radius.circular(12),
    );
    canvas.drawRRect(card, fillPaint);
    canvas.drawRRect(card, strokePaint);
    canvas.drawLine(const Offset(33, 42), const Offset(63, 42), strokePaint);
    canvas.drawLine(const Offset(33, 52), const Offset(52, 52), strokePaint);
    canvas.drawCircle(const Offset(70, 30), 11, accentFill);
    canvas.drawCircle(const Offset(70, 30), 11, accentStroke);
    canvas.drawLine(const Offset(70, 26), const Offset(70, 34), accentStroke);
    canvas.drawLine(const Offset(66, 30), const Offset(74, 30), accentStroke);
  }

  void _paintNoMessages(
    Canvas canvas,
    Paint strokePaint,
    Paint accentStroke,
    Paint fillPaint,
  ) {
    // OD: stacked docs + center plus; Material rx looser.
    final back = RRect.fromRectAndRadius(
      const Rect.fromLTWH(18, 22, 44, 52),
      const Radius.circular(10),
    );
    canvas.drawRRect(back, fillPaint);
    canvas.drawRRect(back, strokePaint);
    canvas.drawLine(const Offset(26, 35), const Offset(52, 35), strokePaint);
    canvas.drawLine(const Offset(26, 44), const Offset(46, 44), strokePaint);
    canvas.drawLine(const Offset(26, 52), const Offset(50, 52), strokePaint);
    final front = RRect.fromRectAndRadius(
      const Rect.fromLTWH(48, 30, 30, 40),
      const Radius.circular(10),
    );
    canvas.drawRRect(front, fillPaint);
    canvas.drawRRect(front, accentStroke);
    canvas.drawLine(const Offset(57, 48), const Offset(70, 48), accentStroke);
    canvas.drawLine(const Offset(63, 42), const Offset(63, 54), accentStroke);
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
