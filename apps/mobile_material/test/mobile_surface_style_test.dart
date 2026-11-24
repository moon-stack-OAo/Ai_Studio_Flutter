import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_material/pages/chat/widgets/composer.dart';
import 'package:mobile_material/pages/settings/widgets/settings_section.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('settings heading fits narrow large-text surface ($dark)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? buildMaterialDarkTheme() : buildMaterialLightTheme(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: const Scaffold(
              body: SettingsSectionCard(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: SettingsSectionHeading(
                    title: '字号与密度 · 设置分组',
                    icon: Icons.text_fields_rounded,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('字号与密度 · 设置分组'), findsOneWidget);
    });
    testWidgets('composer surface and focus retain send behavior ($dark)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? sent;
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? buildMaterialDarkTheme() : buildMaterialLightTheme(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: Composer(
                enabled: true,
                streaming: false,
                onSend: (text) => sent = text,
                onStop: () {},
              ),
            ),
          ),
        ),
      );
      final surface = find
          .descendant(
            of: find.byType(Composer),
            matching: find.byType(AnimatedContainer),
          )
          .first;
      final idle =
          tester.widget<AnimatedContainer>(surface).decoration!
              as BoxDecoration;
      expect(idle.boxShadow, isNotEmpty);
      expect(idle.borderRadius, BorderRadius.circular(24));
      await tester.enterText(find.byType(TextField), '测试消息');
      await tester.pumpAndSettle();
      final focused =
          tester.widget<AnimatedContainer>(surface).decoration!
              as BoxDecoration;
      expect(focused.border, isNot(idle.border));
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final send = find.byIcon(Icons.send_rounded);
      expect(send, findsOneWidget);
      await tester.tap(send);
      await tester.pump();
      expect(sent, '测试消息');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
