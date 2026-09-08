import 'package:core/core.dart';
import 'package:desktop_fluent/pages/image/image_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('跨页生成互斥（ImageController + ChatSessionFacade）', () {
    late GenerationRuntime generation;
    late ProviderRepository providers;
    late ImageSessionRepository imageSessions;
    late ChatSessionRepository chatSessions;
    late ChatDefaultsRepository chatDefaults;
    late ImageController image;
    late ChatSessionFacade chat;

    setUp(() async {
      generation = GenerationRuntime();
      providers = ProviderRepository(
        storage: MemoryProviderStorage(),
        connectionTester: StubProviderConnectionTester(),
      );
      await providers.load();
      await providers.updateProvider(
        providers.activeProviderId,
        baseUrl: 'https://api.example.local/v1',
        apiKey: 'sk-test',
        chatModel: 'gpt-4o',
        imageModel: 'gpt-image-1',
      );

      imageSessions = ImageSessionRepository(
        storage: MemoryImageSessionStorage(),
      );
      await imageSessions.load();

      chatSessions = ChatSessionRepository(
        storage: MemoryChatSessionStorage(),
      );
      await chatSessions.load();

      chatDefaults = ChatDefaultsRepository(
        storage: MemoryChatDefaultsStorage(),
      );
      await chatDefaults.load();

      image = ImageController(
        providerRepository: providers,
        sessionRepository: imageSessions,
        generation: generation,
      );
      chat = ChatSessionFacade(
        providers: providers,
        sessions: chatSessions,
        chatDefaults: chatDefaults,
        generation: generation,
      );
    });

    tearDown(() {
      image.dispose();
      chat.dispose();
    });

    test('空闲时双方门闩可放行', () {
      image.setPromptDraft('一只猫');
      expect(image.canGenerate, isTrue);
      expect(chat.canSend, isTrue);
    });

    test('对话占用 GenerationRuntime 时生图 canGenerate=false', () {
      image.setPromptDraft('一只猫');
      expect(image.canGenerate, isTrue);

      generation.begin('chat-busy', () {});
      expect(generation.busy, isTrue);
      expect(image.canGenerate, isFalse);
      expect(chat.canSend, isFalse);
    });

    test('生图占用 GenerationRuntime 时对话 canSend=false', () {
      image.setPromptDraft('一只猫');
      generation.begin('img-busy', () {});
      expect(image.canGenerate, isFalse);
      expect(chat.canSend, isFalse);
    });

    test('释放后双方门闩恢复', () {
      image.setPromptDraft('一只猫');
      final token = generation.begin('chat-busy', () {});
      expect(image.canGenerate, isFalse);

      generation.end('chat-busy', token);
      expect(generation.busy, isFalse);
      expect(image.canGenerate, isTrue);
      expect(chat.canSend, isTrue);
    });
  });
}
