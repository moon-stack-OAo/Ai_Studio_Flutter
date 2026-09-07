import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('生图预设按 mode 过滤并保留通用项', () {
    final txt = getPromptPresets(PromptDomain.image, mode: 'txt2img');
    expect(txt.any((e) => e.id == 'i-t2i-portrait'), isTrue);
    expect(txt.any((e) => e.id == 'i-common-clean'), isTrue);
    expect(txt.any((e) => e.mode == 'img2img'), isFalse);

    final img = getPromptPresets(PromptDomain.image, mode: 'img2img');
    expect(img.any((e) => e.id == 'i-i2i-style'), isTrue);
    expect(img.any((e) => e.id == 'i-common-clean'), isTrue);
    expect(img.any((e) => e.mode == 'txt2img'), isFalse);
  });

  test('随机预设非空', () {
    final p = pickRandomPromptPreset(PromptDomain.video, mode: 'txt2video');
    expect(p, isNotNull);
    expect(p!.prompt.trim(), isNotEmpty);
  });

  test('supportsImageQuality 与现网规则一致', () {
    expect(
      supportsImageQuality(
        builtin: true,
        type: ProviderType.openai,
        imageModel: 'gpt-image-1',
      ),
      isTrue,
    );
    expect(
      supportsImageQuality(
        builtin: false,
        type: ProviderType.openai,
        imageModel: 'gpt-image-1',
      ),
      isFalse,
    );
    expect(
      supportsImageQuality(
        builtin: true,
        type: ProviderType.xai,
        imageModel: 'grok-imagine-image',
      ),
      isFalse,
    );
    expect(
      supportsImageQuality(
        builtin: true,
        type: ProviderType.xai,
        imageModel: 'grok-imagine-image-2',
      ),
      isTrue,
    );
    expect(
      supportsImageQuality(
        builtin: true,
        type: ProviderType.openaiCompatible,
        imageModel: 'any',
      ),
      isFalse,
    );
  });
}
