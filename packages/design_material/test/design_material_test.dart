import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart'
    show
        Brightness,
        Color,
        Directionality,
        Row,
        TextDirection,
        TextStyle,
        ThemeMode,
        VisualDensity;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('light and dark primary hues differ', () {
    expect(MaterialTokens.light.primary, const Color(0xFFD97757));
    expect(MaterialTokens.dark.primary, const Color(0xFF3B82F6));
    expect(MaterialTokens.light.primary, isNot(MaterialTokens.dark.primary));
    expect(MaterialTokens.light.brightness, Brightness.light);
    expect(MaterialTokens.dark.brightness, Brightness.dark);
  });

  test('theme builders attach tokens extension', () {
    final light = buildMaterialLightTheme();
    final dark = buildMaterialDarkTheme();
    expect(light.extension<MaterialTokens>(), MaterialTokens.light);
    expect(dark.extension<MaterialTokens>(), MaterialTokens.dark);
    expect(light.scaffoldBackgroundColor, MaterialTokens.light.canvas);
    expect(dark.scaffoldBackgroundColor, MaterialTokens.dark.canvas);
  });

  test('ThemePreference maps to ThemeMode and toggles', () {
    expect(ThemePreference.light.themeMode, ThemeMode.light);
    expect(ThemePreference.dark.themeMode, ThemeMode.dark);
    expect(ThemePreference.light.toggled, ThemePreference.dark);
    expect(ThemePreference.dark.toggled, ThemePreference.light);
    expect(ThemePreference.fromWire('dark'), ThemePreference.dark);
    expect(ThemePreference.fromWire('nope'), ThemePreference.light);
  });

  test('AppFontScale factors and wire', () {
    expect(AppFontScale.smaller.factor, 0.85);
    expect(AppFontScale.small.factor, 0.92);
    expect(AppFontScale.standard.factor, 1.0);
    expect(AppFontScale.large.factor, 1.08);
    expect(AppFontScale.larger.factor, 1.15);
    expect(AppFontScale.fromWire('large'), AppFontScale.large);
    expect(AppFontScale.fromWire('x'), AppFontScale.standard);
  });

  test('UiDensity maps visualDensity', () {
    expect(UiDensity.comfortable.visualDensity, VisualDensity.standard);
    expect(UiDensity.compact.visualDensity, VisualDensity.compact);
    expect(UiDensity.fromWire('compact'), UiDensity.compact);
    expect(UiDensity.fromWire(null), UiDensity.compact);
    expect(UiDensity.compact.navigationBarHeight, 64);
    expect(UiDensity.comfortable.navigationBarHeight, 68);
    expect(UiDensity.compact.sessionItemVerticalPadding, 10);
    expect(UiDensity.comfortable.sessionItemVerticalPadding, 14);
  });

  test('theme builders honor fontScale and density', () {
    final scaled = buildMaterialLightTheme(
      fontScale: AppFontScale.larger,
      density: UiDensity.comfortable,
    );
    final base = buildMaterialLightTheme();
    expect(scaled.visualDensity, VisualDensity.standard);
    expect(base.visualDensity, VisualDensity.compact);
    expect(
      scaled.textTheme.bodyMedium!.fontSize,
      closeTo(base.textTheme.bodyMedium!.fontSize! * 1.15, 0.01),
    );
    expect(scaled.navigationBarTheme.height, 68);
    expect(base.navigationBarTheme.height, 64);
  });

  test('Material font stack and mono fallback', () {
    expect(MaterialTokens.fontStackFamily, 'Roboto');
    expect(MaterialTokens.monoStackFamily, 'Roboto Mono');
    expect(MaterialTokens.light.fontFamily, 'Roboto');
    expect(MaterialTokens.light.monoFontFamily, 'Roboto Mono');
    expect(kMaterialFontFamilyFallback, containsAll(<String>[
      'Noto Sans SC',
      '-apple-system',
      'PingFang SC',
      'Microsoft YaHei',
    ]));
    expect(kMaterialMonoFontFamilyFallback, containsAll(<String>[
      'Noto Sans Mono',
      'SF Mono',
      'Consolas',
      'monospace',
    ]));
    final theme = buildMaterialLightTheme();
    expect(theme.textTheme.bodyMedium!.fontFamily, 'Roboto');
    expect(
      theme.textTheme.bodyMedium!.fontFamilyFallback,
      kMaterialFontFamilyFallback,
    );
  });

  test('withMonoFont attaches mono family and fallback', () {
    final style =
        const TextStyle(fontSize: 12).withMonoFont(MaterialTokens.light);
    expect(style.fontFamily, 'Roboto Mono');
    expect(style.fontFamilyFallback, kMaterialMonoFontFamilyFallback);
  });

  testWidgets('NavIcons paint four kinds without throw', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            AppNavIcon(kind: NavIconKind.chat, size: 22),
            AppNavIcon(kind: NavIconKind.image, size: 22, selected: true),
            AppNavIcon(kind: NavIconKind.video, size: 22),
            AppNavIcon(kind: NavIconKind.settings, size: 22, selected: true),
          ],
        ),
      ),
    );
    expect(find.byType(AppNavIcon), findsNWidgets(4));
  });
}

