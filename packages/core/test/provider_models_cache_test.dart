import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProviderModelsCache', () {
    late ProviderRepository providers;
    late ProviderModelsCache cache;

    setUp(() async {
      providers = ProviderRepository(
        storage: MemoryProviderStorage(),
        connectionTester: StubProviderConnectionTester(
          models: const [
            ProviderModelInfo(id: 'm1'),
            ProviderModelInfo(id: 'm2'),
          ],
        ),
      );
      await providers.load();
      final added = await providers.addProvider(
        name: 'Test',
        baseUrl: 'https://example.com/v1',
        apiKey: 'sk-test',
        chatModel: 'chat-1',
        imageModel: 'img-1',
        videoModel: 'vid-1',
      );
      await providers.setActiveProvider(added.id);
      cache = ProviderModelsCache(providers: providers);
    });

    tearDown(() {
      cache.dispose();
    });

    test('load 写入缓存并可复用', () async {
      final list = await cache.load(force: true);
      expect(list.map((e) => e.id), ['m1', 'm2']);
      expect(cache.hasCached, isTrue);
      expect(cache.isFresh, isTrue);
      expect(cache.error, isNull);

      final again = await cache.load(force: false);
      expect(again.map((e) => e.id), ['m1', 'm2']);
    });

    test('canUse 拒绝时直接空列表', () async {
      final list = await cache.load(canUse: (_) => false);
      expect(list, isEmpty);
      expect(cache.loading, isFalse);
      expect(cache.hasCached, isFalse);
    });
  });
}
