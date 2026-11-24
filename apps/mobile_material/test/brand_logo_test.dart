import 'dart:ui' as ui;

import 'package:mobile_material/shell/brand_intro_gate.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'startup logo decodes and paints (${dark ? 'dark' : 'light'})',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? buildMaterialDarkTheme() : buildMaterialLightTheme(),
            home: const BrandIntroGate(
              displayDuration: Duration(seconds: 30),
              child: SizedBox(),
            ),
          ),
        );
        await tester.runAsync(() async {
          final data = await rootBundle.load('assets/logo.png');
          final codec = await ui.instantiateImageCodec(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          );
          final frame = await codec.getNextFrame();
          expect(frame.image.width, 512);
          frame.image.dispose();
          codec.dispose();
          await precacheImage(
            const AssetImage('assets/logo.png'),
            tester.element(find.byType(BrandIntroGate)),
          );
        });
        await tester.pump();
        expect(tester.takeException(), isNull);
        final image = tester.widget<RawImage>(find.byType(RawImage));
        expect(image.image, isNotNull);
        expect(
          tester.getSize(find.byType(RawImage)).shortestSide,
          greaterThan(40),
        );
        await tester.pump(const Duration(seconds: 29));
        expect(find.text('AI Studio'), findsOneWidget);
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('AI Studio'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
