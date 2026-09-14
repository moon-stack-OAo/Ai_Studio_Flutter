import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VideoPlaybackErrors', () {
    test('常量文案', () {
      expect(VideoPlaybackErrors.noAddress, contains('地址'));
      expect(VideoPlaybackErrors.memoryOnly, contains('另存'));
      expect(VideoPlaybackErrors.localMissing, contains('不存在'));
    });

    test('initFailed 本地保留短原因', () {
      final msg = VideoPlaybackErrors.initFailed('boom');
      expect(msg, startsWith('播放器初始化失败'));
      expect(msg, contains('boom'));
    });

    test('initFailed 远端弱网主句中文', () {
      final msg = VideoPlaybackErrors.initFailed(
        'SocketException: Failed host lookup',
        isRemote: true,
      );
      expect(msg, startsWith('无法加载远端视频'));
      expect(msg, isNot(contains('SocketException')));
    });

    test('streamFailed 远端超时', () {
      final msg = VideoPlaybackErrors.streamFailed(
        'Connection timed out',
        isRemote: true,
      );
      expect(msg, startsWith('播放中断'));
      expect(msg, contains('超时'));
    });

    test('streamFailed 本地解码', () {
      final msg = VideoPlaybackErrors.streamFailed('Unsupported codec');
      expect(msg, startsWith('播放出错'));
      expect(msg, contains('解码'));
    });

    test('looksNetwork', () {
      expect(VideoPlaybackErrors.looksNetwork('timeout'), isTrue);
      expect(VideoPlaybackErrors.looksNetwork('ok'), isFalse);
    });
  });
}
