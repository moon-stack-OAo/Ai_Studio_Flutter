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
    expect(UiDensity.compact.composerPadding.left, 12);
    expect(UiDensity.comfortable.composerPadding.left, 14);
    expect(UiDensity.compact.settingsFormGap, 10);
    expect(UiDensity.comfortable.settingsFormGap, 14);
    expect(UiDensity.compact.settingsCardPadding, 12);
    expect(UiDensity.comfortable.settingsCardPadding, 16);
  });

  test('tokens expose scrim and surface ladder', () {
    expect(MaterialTokens.light.scrim, const Color(0xB8141413));
    expect(MaterialTokens.dark.scrim, const Color(0xCC000000));
    expect(
      MaterialTokens.light.canvas,
      isNot(MaterialTokens.light.surfaceMuted),
    );
    expect(
      MaterialTokens.dark.surfaceElevated,
      isNot(MaterialTokens.dark.canvas),
    );
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
    // E9：compact/comfortable + 更大字号抬高底栏，避免 label 裁切。
    expect(scaled.navigationBarTheme.height, 78);
    expect(base.navigationBarTheme.height, 64);
    expect(
      UiDensity.compact.navigationBarHeightFor(AppFontScale.larger.factor),
      74,
    );
    expect(
      UiDensity.comfortable.navigationBarHeightFor(AppFontScale.smaller.factor),
      68,
    );
  });

  test('extreme density+fontScale spacing stays usable', () {
    // E9 抽检：compact+更大 / comfortable+更小 主路径间距仍为正且可区分。
    expect(UiDensity.compact.sessionItemVerticalPadding, lessThan(
      UiDensity.comfortable.sessionItemVerticalPadding,
    ));
    expect(UiDensity.compact.composerPadding.top, greaterThan(0));
    expect(UiDensity.comfortable.settingsFormGap, greaterThan(0));
    final tight = buildMaterialLightTheme(
      fontScale: AppFontScale.larger,
      density: UiDensity.compact,
    );
    final loose = buildMaterialLightTheme(
      fontScale: AppFontScale.smaller,
      density: UiDensity.comfortable,
    );
    expect(tight.visualDensity, VisualDensity.compact);
    expect(loose.visualDensity, VisualDensity.standard);
    expect(
      tight.textTheme.bodyMedium!.fontSize!,
      greaterThan(loose.textTheme.bodyMedium!.fontSize!),
    );
    expect(tight.navigationBarTheme.height, 74);
    expect(loose.navigationBarTheme.height, 68);
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

