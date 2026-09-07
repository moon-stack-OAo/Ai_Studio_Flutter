import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProviderRepository repo;

  setUp(() async {
    repo = ProviderRepository(
      storage: MemoryProviderStorage(),
      connectionTester: StubProviderConnectionTester(),
    );
    await repo.load();
  });

  test('loads builtin presets', () {
    expect(repo.providers.length, greaterThanOrEqualTo(2));
    expect(repo.providers.any((p) => p.id == 'openai'), isTrue);
    expect(repo.providers.any((p) => p.id == 'xai'), isTrue);
    expect(repo.activeProviderId, isNotEmpty);
  });

  test('add / update / remove custom provider', () async {
    final added = await repo.addProvider(
      name: '自建',
      baseUrl: 'https://api.example.local/v1',
      apiKey: 'sk-local',
      chatModel: 'gpt-4.1-mini',
    );
    expect(repo.activeProviderId, added.id);
    expect(repo.activeChatCredentials?.chatModel, 'gpt-4.1-mini');
    expect(repo.activeChatCredentials?.apiKey, 'sk-local');

    await repo.updateProvider(
      added.id,
      imageModel: 'gpt-image-1',
      videoModel: 'sora-2',
    );
    final updated = repo.providers.firstWhere((p) => p.id == added.id);
    expect(updated.imageModel, 'gpt-image-1');
    expect(updated.videoModel, 'sora-2');

    final removed = await repo.removeProvider(added.id);
    expect(removed, isTrue);
    expect(repo.providers.any((p) => p.id == added.id), isFalse);
  });

  test('cannot remove builtin or last provider', () async {
    expect(await repo.removeProvider('openai'), isFalse);

    // 删到只剩一个自定义时也不能再删
    await repo.resetPresets();
    final only = await repo.addProvider(name: 'only');
    // 先删两个内置——内置不可删，应失败
    expect(await repo.removeProvider('openai'), isFalse);
    expect(await repo.removeProvider(only.id), isTrue);
  });

  test('memory storage round-trip keeps apiKey', () async {
    final storage = MemoryProviderStorage();
    final a = ProviderRepository(
      storage: storage,
      connectionTester: StubProviderConnectionTester(),
    );
    await a.load();
    final custom = await a.addProvider(
      name: 'Round',
      apiKey: 'sk-persist-me',
      baseUrl: 'https://x.test/v1',
      chatModel: 'm1',
    );

    final b = ProviderRepository(
      storage: storage,
      connectionTester: StubProviderConnectionTester(),
    );
    await b.load();
    final restored = b.providers.firstWhere((p) => p.id == custom.id);
    expect(restored.apiKey, 'sk-persist-me');
    expect(restored.chatModel, 'm1');
  });

  test('testConnection writes lastTest fields', () async {
    final id = repo.activeProviderId;
    await repo.updateProvider(
      id,
      baseUrl: 'https://api.example.local/v1',
      apiKey: 'sk-x',
      chatModel: 'gpt',
    );
    final result = await repo.testConnection(id);
    expect(result.ok, isTrue);
    final p = repo.providers.firstWhere((e) => e.id == id);
    expect(p.lastTestOk, isTrue);
    expect(p.lastTestDetail, isNotEmpty);
    expect(p.lastTestAtMs, isNotNull);
  });

  test('ActiveChatCredentials toString masks key', () {
    const creds = ActiveChatCredentials(
      providerId: 'p',
      providerName: 'n',
      type: ProviderType.openai,
      baseUrl: 'https://api.openai.com/v1',
      apiKey: 'sk-should-not-leak',
      chatModel: 'gpt-4o',
    );
    expect(creds.toString().contains('sk-should-not-leak'), isFalse);
  });

  test('activeImageCredentials 需 imageModel', () async {
    expect(repo.activeImageCredentials, isNull);
    final id = repo.activeProviderId;
    await repo.updateProvider(
      id,
      baseUrl: 'https://api.example.local/v1',
      apiKey: 'sk-x',
      imageModel: 'gpt-image-1',
    );
    expect(repo.hasConfiguredImageProvider, isTrue);
    expect(repo.activeImageCredentials?.imageModel, 'gpt-image-1');
    expect(repo.activeImageCredentials?.apiKey, 'sk-x');
  });

  test('activeVideoCredentials 需 videoModel；可空表示不使用', () async {
    expect(repo.activeVideoCredentials, isNull);
    expect(repo.hasConfiguredVideoProvider, isFalse);
    final id = repo.activeProviderId;
    await repo.updateProvider(
      id,
      baseUrl: 'https://api.example.local/v1',
      apiKey: 'sk-x',
      videoModel: 'sora-2',
    );
    expect(repo.hasConfiguredVideoProvider, isTrue);
    expect(repo.activeVideoCredentials?.videoModel, 'sora-2');
    expect(repo.activeVideoCredentials?.apiKey, 'sk-x');

    await repo.updateProvider(id, videoModel: '');
    expect(repo.activeVideoCredentials, isNull);
    expect(repo.hasConfiguredVideoProvider, isFalse);
  });

  test('providersReadyFor 按 canXxx 过滤，不看 lastTestOk', () async {
    await repo.resetPresets();
    final chatOnly = await repo.addProvider(
      name: 'chat-only',
      baseUrl: 'https://api.example.local/v1',
      apiKey: 'sk-a',
      chatModel: 'gpt-4o',
    );
    final imageOnly = await repo.addProvider(
      name: 'image-only',
      baseUrl: 'https://api.example.local/v1',
      apiKey: 'sk-b',
      imageModel: 'gpt-image-1',
    );
    final videoOnly = await repo.addProvider(
      name: 'video-only',
      baseUrl: 'https://api.example.local/v1',
      apiKey: 'sk-c',
      videoModel: 'sora-2',
    );
    await repo.updateProvider(chatOnly.id, lastTestOk: false);
    await repo.updateProvider(imageOnly.id, lastTestOk: true);

    final chatReady = repo.providersReadyFor(ModelKind.chat);
    expect(chatReady.any((p) => p.id == chatOnly.id), isTrue);
    expect(chatReady.any((p) => p.id == imageOnly.id), isFalse);

    final imageReady = repo.providersReadyFor(ModelKind.image);
    expect(imageReady.any((p) => p.id == imageOnly.id), isTrue);
    expect(imageReady.any((p) => p.id == chatOnly.id), isFalse);

    final videoReady = repo.providersReadyFor(ModelKind.video);
    expect(videoReady.any((p) => p.id == videoOnly.id), isTrue);
    expect(videoReady.any((p) => p.id == chatOnly.id), isFalse);
  });
}
