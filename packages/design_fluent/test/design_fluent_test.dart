import 'package:design_fluent/design_fluent.dart';
import 'package:flutter/material.dart'
    show
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
    expect(FluentTokens.light.primary, const Color(0xFFD97757));
    expect(FluentTokens.dark.primary, const Color(0xFF3B82F6));
    expect(FluentTokens.light.primary, isNot(FluentTokens.dark.primary));
  });

  test('theme builders attach tokens extension', () {
    final light = buildFluentLightTheme();
    final dark = buildFluentDarkTheme();
    expect(light.extension<FluentTokens>(), FluentTokens.light);
    expect(dark.extension<FluentTokens>(), FluentTokens.dark);
    expect(light.scaffoldBackgroundColor, FluentTokens.light.canvas);
    expect(dark.scaffoldBackgroundColor, FluentTokens.dark.canvas);
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
    expect(UiDensity.fromWire(null), UiDensity.comfortable);
    expect(UiDensity.compact.settingsCatWidth, 232);
    expect(UiDensity.comfortable.settingsCatWidth, 260);
    expect(UiDensity.compact.sessionItemVerticalPadding, 5);
    expect(UiDensity.comfortable.sessionItemVerticalPadding, 8);
    expect(UiDensity.compact.composerPadding.top, 8);
    expect(UiDensity.comfortable.composerPadding.top, 12);
    expect(UiDensity.compact.settingsFormGap, 8);
    expect(UiDensity.comfortable.settingsFormGap, 12);
    expect(UiDensity.compact.settingsCatTileVertical, 7);
    expect(UiDensity.comfortable.settingsCatTileVertical, 10);
  });

  test('tokens expose scrim and surface ladder', () {
    expect(FluentTokens.light.scrim, const Color(0xB8141413));
    expect(FluentTokens.dark.scrim, const Color(0xCC000000));
    expect(FluentTokens.light.canvas, isNot(FluentTokens.light.surfaceMuted));
    expect(
      FluentTokens.dark.surfaceElevated,
      isNot(FluentTokens.dark.canvas),
    );
  });

  test('theme builders honor fontScale and density', () {
    final scaled = buildFluentLightTheme(
      fontScale: AppFontScale.larger,
      density: UiDensity.compact,
    );
    final base = buildFluentLightTheme();
    expect(scaled.visualDensity, VisualDensity.compact);
    expect(
      scaled.typography.body!.fontSize,
      closeTo(base.typography.body!.fontSize! * 1.15, 0.01),
    );
    expect(scaled.extension<FluentTokens>()!.settingsCatWidth, 232);
    expect(base.extension<FluentTokens>()!.settingsCatWidth, 260);
  });

  test('Fluent font stack and typography fallback', () {
    expect(FluentTokens.fontStackFamily, 'Segoe UI Variable');
    expect(FluentTokens.monoStackFamily, 'Cascadia Code');
    expect(FluentTokens.light.fontFamily, 'Segoe UI Variable');
    expect(FluentTokens.light.monoFontFamily, 'Cascadia Code');
    expect(kFluentFontFamilyFallback, containsAll(<String>[
      'Segoe UI',
      '-apple-system',
      'PingFang SC',
      'Microsoft YaHei',
    ]));
    expect(kFluentMonoFontFamilyFallback, containsAll(<String>[
      'Cascadia Mono',
      'SF Mono',
      'Consolas',
      'Microsoft YaHei Mono',
      'monospace',
    ]));
    final theme = buildFluentLightTheme();
    expect(theme.typography.body!.fontFamily, 'Segoe UI Variable');
    expect(
      theme.typography.body!.fontFamilyFallback,
      kFluentFontFamilyFallback,
    );
  });

  test('withMonoFont attaches mono family and fallback', () {
    final style = const TextStyle(fontSize: 12).withMonoFont(FluentTokens.light);
    expect(style.fontFamily, 'Cascadia Code');
    expect(style.fontFamilyFallback, kFluentMonoFontFamilyFallback);
  });

  testWidgets('NavIcons paint four kinds without throw', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            AppNavIcon(kind: NavIconKind.chat, size: 18),
            AppNavIcon(kind: NavIconKind.image, size: 18, selected: true),
            AppNavIcon(kind: NavIconKind.video, size: 18),
            AppNavIcon(kind: NavIconKind.settings, size: 18, selected: true),
          ],
        ),
      ),
    );
    expect(find.byType(AppNavIcon), findsNWidgets(4));
  });
}

