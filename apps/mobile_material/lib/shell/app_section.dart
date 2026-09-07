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

  /// 能力 ID（原型 badge）。
  String get capabilityId => switch (this) {
        AppSection.chat => 'CHAT',
        AppSection.image => 'IMG',
        AppSection.video => 'VID',
        AppSection.settings => 'SET',
      };
}
