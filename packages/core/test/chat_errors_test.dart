import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('friendlyUpstreamErrorMessage', () {
    test('视频队列已满', () {
      expect(
        friendlyUpstreamErrorMessage(
          'video queue is full, please retry later '
          '(request id: 20260918085312719562631l99DlByO)',
        ),
        '视频生成队列已满，请稍后再试',
      );
      expect(
        friendlyUpstreamErrorMessage('The queue is full'),
        '视频生成队列已满，请稍后再试',
      );
    });

    test('未命中则原样', () {
      expect(friendlyUpstreamErrorMessage('自定义业务错误'), '自定义业务错误');
    });
  });

  group('sanitizeErrorText', () {
    test('脱敏路径也会映射队列满', () {
      expect(
        sanitizeErrorText(
          'ERROR · video · video queue is full, please retry later',
        ),
        '视频生成队列已满，请稍后再试',
      );
    });
  });
}
