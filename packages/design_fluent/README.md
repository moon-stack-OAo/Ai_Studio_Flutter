# design_fluent

Fluent 桌面设计 token 与主题（亮色 Claude 向 / 暗色 Cursor 向；Segoe 系系统字体）。供 `apps/desktop_fluent` 使用，禁止与 Material 侧 Widget 互引。

规格与包边界见仓库根目录 [`DESIGN.md`](../../DESIGN.md)、[`AGENTS.md`](../../AGENTS.md)。

```dart
FluentApp(
  themeMode: ThemeMode.light, // 或 ThemeMode.dark；不提供跟随系统
  theme: buildFluentLightTheme(),
  darkTheme: buildFluentDarkTheme(),
  home: ...,
);

final tokens = fluentTokensOf(context);
```
