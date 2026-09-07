import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('stripEnhancedPrompt', () {
    test('剥离 markdown fence 与引号', () {
      expect(stripEnhancedPrompt('```\nhello\n```'), 'hello');
      expect(stripEnhancedPrompt('"world"'), 'world');
      expect(stripEnhancedPrompt('「中文」'), '中文');
      expect(stripEnhancedPrompt(null), '');
      expect(stripEnhancedPrompt('  plain  '), 'plain');
    });
  });

  group('resolveEnhanceSystemPrompt', () {
    test('图像 / 视频基座文案', () {
      final image = resolveEnhanceSystemPrompt(PromptDomain.image);
      expect(image, contains('图像生成提示词优化助手'));
      expect(image, isNot(contains('图生图')));

      final video = resolveEnhanceSystemPrompt(PromptDomain.video);
      expect(video, contains('视频生成提示词优化助手'));
    });

    test('img2img / img2video 附加 mode hint', () {
      final i2i = resolveEnhanceSystemPrompt(PromptDomain.image, 'img2img');
      expect(i2i, contains('图生图'));
      expect(i2i, contains('不要推翻或替换主体'));

      final i2v = resolveEnhanceSystemPrompt(PromptDomain.video, 'img2video');
      expect(i2v, contains('图生视频'));
      expect(i2v, contains('镜头运动'));
    });

    test('未知 mode 不加 hint', () {
      final t = resolveEnhanceSystemPrompt(PromptDomain.image, 'txt2img');
      expect(t, equals(enhanceSystemImage));
    });
  });
}
