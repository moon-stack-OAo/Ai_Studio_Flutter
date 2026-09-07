import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProviderConfig', () {
    test('round-trip meta json without apiKey', () {
      const original = ProviderConfig(
        id: 'p1',
        name: 'Demo',
        type: ProviderType.openaiCompatible,
        baseUrl: 'https://api.example.local/v1',
        apiKey: 'sk-secret-value',
        chatModel: 'gpt-4.1-mini',
        imageModel: 'gpt-image-1',
        videoModel: '',
        lastTestOk: true,
        lastTestDetail: 'ok',
        lastTestAtMs: 100,
      );

      final meta = original.toJsonMeta();
      expect(meta.containsKey('apiKey'), isFalse);

      final restored = ProviderConfig.fromJson(meta, apiKey: 'sk-secret-value');
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.type, ProviderType.openaiCompatible);
      expect(restored.baseUrl, original.baseUrl);
      expect(restored.apiKey, 'sk-secret-value');
      expect(restored.chatModel, 'gpt-4.1-mini');
      expect(restored.imageModel, 'gpt-image-1');
      expect(restored.videoModel, '');
      expect(restored.lastTestOk, isTrue);
    });

    test('maskedApiKey never exposes full secret', () {
      const p = ProviderConfig(
        id: 'p1',
        name: 'Demo',
        type: ProviderType.openai,
        apiKey: 'sk-abcdefghijklmnopqrstuvwxyz',
      );
      expect(p.maskedApiKey.contains('abcdefghijklmnop'), isFalse);
      expect(p.toString().contains('sk-abcdefghijklmnopqrstuvwxyz'), isFalse);
      expect(p.canChat, isFalse);
    });

    test('canImage requires url + key + imageModel', () {
      const base = ProviderConfig(
        id: 'p',
        name: 't',
        type: ProviderType.openai,
        baseUrl: 'https://x',
        apiKey: 'sk',
        imageModel: 'gpt-image-1',
      );
      expect(base.canImage, isTrue);
      expect(
        base.copyWith(imageModel: '').canImage,
        isFalse,
      );
    });

    test('canChat requires url + key + chatModel', () {
      const ready = ProviderConfig(
        id: 'p1',
        name: 'Demo',
        type: ProviderType.openai,
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-test',
        chatModel: 'gpt-4o',
      );
      expect(ready.canChat, isTrue);
    });
  });

  group('ProviderType', () {
    test('fromWire maps aliases', () {
      expect(ProviderType.fromWire('openai'), ProviderType.openai);
      expect(ProviderType.fromWire('xai'), ProviderType.xai);
      expect(
        ProviderType.fromWire('openai-compatible'),
        ProviderType.openaiCompatible,
      );
      expect(
        ProviderType.fromWire('unknown'),
        ProviderType.openaiCompatible,
      );
    });
  });
}
