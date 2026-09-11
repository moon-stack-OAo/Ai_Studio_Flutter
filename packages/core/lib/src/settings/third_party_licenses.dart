/// 关于页（`SET-ABOUT`）第三方播放 / 编解码库许可说明。
///
/// 双端视频播放依赖 `media_kit` 家族；原生侧经 `media_kit_libs_video`
/// 动态链接 libmpv，并捆绑其依赖的 FFmpeg（LGPL 构建）。
/// 文案保持简短产品语气，不展开法律全文。
class ThirdPartyLicenseEntry {
  const ThirdPartyLicenseEntry({
    required this.name,
    required this.license,
    required this.note,
    this.homepageUrl,
  });

  final String name;
  final String license;
  final String note;
  final String? homepageUrl;
}

abstract final class ThirdPartyLicenses {
  static const String dialogTitle = '开源许可';

  static const String playbackSectionTitle = '第三方播放 / 编解码库';

  static const String playbackLead =
      '本应用使用下列库进行本地视频预览。相关原生库为动态链接；'
      'LGPL 组件可按各自许可条款获取对应源码。';

  static const List<ThirdPartyLicenseEntry> playbackLibraries = [
    ThirdPartyLicenseEntry(
      name: 'media_kit / media_kit_video / media_kit_libs_video',
      license: 'MIT',
      note: '跨端播放与视频渲染；原生依赖由 media_kit_libs_video 提供。',
      homepageUrl: 'https://github.com/media-kit/media-kit',
    ),
    ThirdPartyLicenseEntry(
      name: 'libmpv',
      license: 'LGPL-2.1+',
      note: '由 media_kit 动态链接的播放内核（随平台捆绑共享库）。',
      homepageUrl: 'https://mpv.io/',
    ),
    ThirdPartyLicenseEntry(
      name: 'FFmpeg',
      license: 'LGPL-2.1+',
      note: '随 libmpv 捆绑的编解码库（media_kit 默认 LGPL 构建）。',
      homepageUrl: 'https://ffmpeg.org/',
    ),
  ];

  /// 便于一键复制的纯文本摘要。
  static String copyablePlaybackNotice() {
    final buf = StringBuffer()
      ..writeln(playbackSectionTitle)
      ..writeln(playbackLead)
      ..writeln();
    for (final e in playbackLibraries) {
      buf.writeln('· ${e.name}');
      buf.writeln('  许可：${e.license}');
      buf.writeln('  ${e.note}');
      final url = e.homepageUrl;
      if (url != null && url.isNotEmpty) {
        buf.writeln('  $url');
      }
      buf.writeln();
    }
    return buf.toString().trimRight();
  }
}
