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

  group('promptEnhanceSkills', () {
    test('内置风格 id / label 齐全且默认 balanced', () {
      expect(
        promptEnhanceSkills.map((s) => s.id).toList(),
        ['balanced', 'concise', 'cinematic', 'photoreal', 'preserve'],
      );
      expect(defaultPromptEnhanceSkill.id, 'balanced');
      expect(defaultPromptEnhanceSkill.label, '均衡');
      expect(promptEnhanceSkillById('concise')?.label, '精简');
      expect(promptEnhanceSkillById('nope'), isNull);
      expect(resolvePromptEnhanceSkill().id, 'balanced');
      expect(resolvePromptEnhanceSkill(skillId: 'photoreal').id, 'photoreal');
      expect(
        resolvePromptEnhanceSkill(
          skill: promptEnhanceSkillPreserve,
          skillId: 'cinematic',
        ).id,
        'preserve',
      );
    });

    test('各风格采样参数合理', () {
      expect(defaultEnhanceTemperature, 0.4);
      expect(promptEnhanceSkillConcise.maxTokens,
          lessThan(promptEnhanceSkillBalanced.maxTokens));
      expect(promptEnhanceSkillCinematic.maxTokens,
          greaterThan(promptEnhanceSkillBalanced.maxTokens));
      expect(promptEnhanceSkillCinematic.maxTokens,
          lessThanOrEqualTo(defaultEnhanceMaxTokens));
      expect(promptEnhanceSkillPreserve.temperature,
          lessThan(defaultEnhanceTemperature));
    });
  });

  group('resolveEnhanceSystemPrompt', () {
    test('图像 / 视频基座含保真与结构要点', () {
      final image = resolveEnhanceSystemPrompt(PromptDomain.image, null);
      expect(image, contains('图像生成提示词优化助手'));
      expect(image, contains('保真'));
      expect(image, contains('主体 → 场景 → 构图'));
      expect(image, contains('禁止空洞堆砌'));
      expect(image, contains('只输出优化后提示词正文'));
      expect(image, contains('润色风格=均衡'));
      expect(image, isNot(contains('图生图')));
      expect(image, isNot(contains('镜头运动/节奏')));

      final video = resolveEnhanceSystemPrompt(PromptDomain.video, null);
      expect(video, contains('视频生成提示词优化助手'));
      expect(video, contains('镜头运动/节奏'));
      expect(video, contains('润色风格=均衡'));
    });

    test('img2img / img2video / txt2img / txt2video 附加 mode hint', () {
      final i2i = resolveEnhanceSystemPrompt(PromptDomain.image, 'img2img');
      expect(i2i, contains('图生图'));
      expect(i2i, contains('不要推翻或替换主体'));

      final i2v = resolveEnhanceSystemPrompt(PromptDomain.video, 'img2video');
      expect(i2v, contains('图生视频'));
      expect(i2v, contains('镜头运动'));

      final t2i = resolveEnhanceSystemPrompt(PromptDomain.image, 'txt2img');
      expect(t2i, contains('文生图'));
      expect(t2i, isNot(equals(enhanceSystemImage)));
      expect(t2i, contains('不要假设存在参考图'));

      final t2v = resolveEnhanceSystemPrompt(PromptDomain.video, 'txt2video');
      expect(t2v, contains('文生视频'));
      expect(t2v, contains('镜头运动'));
    });

    test('未知 mode 不加 mode hint，仍带默认 skill', () {
      final t = resolveEnhanceSystemPrompt(PromptDomain.image, 'unknown-mode');
      expect(t, isNot(contains('当前为')));
      expect(t, contains(enhanceSystemImage));
      expect(t, contains('润色风格=均衡'));
    });

    test('各 skill 的 systemExtra 拼入', () {
      for (final skill in promptEnhanceSkills) {
        final s = resolveEnhanceSystemPrompt(
          PromptDomain.image,
          null,
          skill: skill,
        );
        expect(s, contains(skill.systemExtra));
        expect(s, contains(enhanceSystemImage));
      }

      final byId = resolveEnhanceSystemPrompt(
        PromptDomain.video,
        'txt2video',
        skillId: 'cinematic',
      );
      expect(byId, contains('润色风格=电影感'));
      expect(byId, contains('文生视频'));
    });
  });
}
