import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('playback notice lists media_kit, libmpv, FFmpeg with URLs', () {
    final text = ThirdPartyLicenses.copyablePlaybackNotice();
    expect(text, contains('media_kit'));
    expect(text, contains('libmpv'));
    expect(text, contains('FFmpeg'));
    expect(text, contains('LGPL'));
    expect(text, contains('https://github.com/media-kit/media-kit'));
    expect(text, contains('https://mpv.io/'));
    expect(text, contains('https://ffmpeg.org/'));
    expect(ThirdPartyLicenses.playbackLibraries, isNotEmpty);
  });
}
