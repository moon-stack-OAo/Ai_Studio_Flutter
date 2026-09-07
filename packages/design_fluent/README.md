# design_fluent

Fluent 桌面设计 token 与主题（亮色 Claude 向 / 暗色 Cursor 向）。

```dart
FluentApp(
  themeMode: ThemeMode.light, // 或 ThemeMode.dark；不提供跟随系统
  theme: buildFluentLightTheme(),
  darkTheme: buildFluentDarkTheme(),
  home: ...,
);

final tokens = fluentTokensOf(context);
```
