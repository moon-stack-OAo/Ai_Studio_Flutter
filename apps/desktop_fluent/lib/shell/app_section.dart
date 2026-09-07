enum AppSection {
  chat,
  image,
  video,
  settings;

  String get label => switch (this) {
        AppSection.chat => '对话',
        AppSection.image => '生图',
        AppSection.video => '生视频',
        AppSection.settings => '设置',
      };
}

enum SettingsCategory {
  providers,
  chatDefaults,
  appearance,
  logs,
  about;

  String get label => switch (this) {
        SettingsCategory.providers => '提供商',
        SettingsCategory.chatDefaults => '对话默认',
        SettingsCategory.appearance => '外观',
        SettingsCategory.logs => '日志',
        SettingsCategory.about => '关于与更新',
      };

  String get description => switch (this) {
        SettingsCategory.providers => '密钥 · 连接 · 模型',
        SettingsCategory.chatDefaults => '温度 · Tokens · 裁剪',
        SettingsCategory.appearance => '主题 · 字号 · 密度',
        SettingsCategory.logs => '筛选 · 复制 · 清空',
        SettingsCategory.about => '版本 · 关闭 · 更新',
      };
}
