import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// 设置页统一排版；沿用 Fluent 字体栈及外观字号倍率。
class SettingsTextStyles {
  SettingsTextStyles(BuildContext context)
    : _tokens = fluentTokensOf(context),
      // caption 的基准始终为 12，嵌套设置主题时也不会重复缩放。
      _factor =
          (FluentTheme.of(context).typography.caption?.fontSize ?? 12) / 12;

  final FluentTokens _tokens;
  final double _factor;

  TextStyle _style(double size, FontWeight weight, Color color) => TextStyle(
    fontFamily: _tokens.fontFamily,
    fontFamilyFallback: kFluentFontFamilyFallback,
    fontSize: size * _factor,
    fontWeight: weight,
    height: 1.4,
    color: color,
  );

  TextStyle get pageTitle => _style(20, FontWeight.w600, _tokens.ink);
  TextStyle get paneTitle => _style(16, FontWeight.w600, _tokens.ink);
  TextStyle get sectionTitle =>
      _style(14, FontWeight.w600, _tokens.inkSecondary);
  TextStyle get label => _style(13, FontWeight.w600, _tokens.inkSecondary);
  TextStyle get body => _style(13, FontWeight.w400, _tokens.ink);
  TextStyle get caption => _style(12, FontWeight.w400, _tokens.inkMuted);
  TextStyle get badge => _style(12, FontWeight.w600, _tokens.inkSecondary);
  TextStyle get code => body.withMonoFont(_tokens);
}

extension SettingsTypographyContext on BuildContext {
  SettingsTextStyles get settingsText => SettingsTextStyles(this);
}

/// 同步控件默认文字，确保 TextBox、ComboBox、按钮与手写标签字号一致。
class SettingsTypography extends StatelessWidget {
  const SettingsTypography({super.key, required this.child, this.color});

  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final text = context.settingsText;
    return FluentTheme(
      data: theme.copyWith(
        typography: theme.typography.merge(
          Typography.raw(
            body: text.body,
            bodyStrong: text.label,
            caption: text.caption,
          ),
        ),
      ),
      child: DefaultTextStyle.merge(
        style: text.body,
        child: color == null ? child : ColoredBox(color: color!, child: child),
      ),
    );
  }
}
