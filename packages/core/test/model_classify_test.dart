import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('classifyModelId', () {
    test('classifies video / image / chat / other', () {
      expect(classifyModelId('sora-2'), ModelKind.video);
      expect(classifyModelId('grok-imagine-video'), ModelKind.video);
      expect(classifyModelId('agnes-video-2.5'), ModelKind.video);
      expect(classifyModelId('agnes-video-v2.0'), ModelKind.video);
      expect(classifyModelId('gpt-image-1'), ModelKind.image);
      expect(classifyModelId('dall-e-3'), ModelKind.image);
      expect(classifyModelId('agnes-image-2.5-flash'), ModelKind.image);
      expect(classifyModelId('gpt-4o'), ModelKind.chat);
      expect(classifyModelId('grok-4.5'), ModelKind.chat);
      expect(classifyModelId('agnes-2.5-flash'), ModelKind.chat);
      expect(classifyModelId('text-embedding-3'), ModelKind.other);
      expect(classifyModelId('whisper-1'), ModelKind.other);
    });
  });

  group('modelOptionsByKind', () {
    final models = [
      const ProviderModelInfo(id: 'gpt-4o'),
      const ProviderModelInfo(id: 'gpt-image-1'),
      const ProviderModelInfo(id: 'sora-2'),
      const ProviderModelInfo(id: 'text-embedding-3'),
    ];

    test('filters by kind and appends manual current', () {
      final chat = modelOptionsByKind(
        models,
        ModelKind.chat,
        current: 'custom-chat',
      );
      expect(chat.map((e) => e.value), containsAll(['gpt-4o', 'custom-chat']));
      expect(
        chat.firstWhere((e) => e.value == 'custom-chat').manual,
        isTrue,
      );
      expect(
        chat.firstWhere((e) => e.value == 'custom-chat').label,
        'custom-chat（手动）',
      );

      final image = modelOptionsByKind(models, ModelKind.image);
      expect(image.map((e) => e.value), ['gpt-image-1']);

      final video = modelOptionsByKind(models, ModelKind.video);
      expect(video.map((e) => e.value), ['sora-2']);
    });

    test('falls back to full list when kind filter empty', () {
      final onlyChat = [const ProviderModelInfo(id: 'my-proxy-model')];
      final image = modelOptionsByKind(onlyChat, ModelKind.image);
      expect(image.map((e) => e.value), ['my-proxy-model']);
    });
  });
}
