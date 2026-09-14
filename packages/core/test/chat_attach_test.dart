import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

final _tinyPng = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  ),
);

void main() {
  group('supportsChatVision', () {
    test('命中启发式', () {
      expect(supportsChatVision('gpt-4o'), isTrue);
      expect(supportsChatVision('GPT-4.1-mini'), isTrue);
      expect(supportsChatVision('o1-preview'), isTrue);
      expect(supportsChatVision('claude-3-5-sonnet'), isTrue);
      expect(supportsChatVision('gemini-2.0-flash'), isTrue);
      expect(supportsChatVision('llava-1.5'), isTrue);
      expect(supportsChatVision('my-vision-model'), isTrue);
    });

    test('未命中', () {
      expect(supportsChatVision(null), isFalse);
      expect(supportsChatVision(''), isFalse);
      expect(supportsChatVision('gpt-3.5-turbo'), isFalse);
      expect(supportsChatVision('deepseek-chat'), isFalse);
    });
  });

  group('ChatMessage attachments', () {
    test('roundtrip + 旧 JSON 无字段 → []', () {
      final msg = ChatMessage(
        id: 'm1',
        createdAt: 1,
        role: ChatRole.user,
        content: '看图',
        attachments: [
          const ImageRef(type: ImageRefType.file, src: '/tmp/a.png'),
          const ImageRef(type: ImageRefType.file, src: '/tmp/b.png'),
        ],
      );
      final back = ChatMessage.fromJson(msg.toJson());
      expect(back.attachments, hasLength(2));
      expect(back.attachments.first.src, '/tmp/a.png');

      final legacy = ChatMessage.fromJson({
        'id': 'old',
        'createdAt': 1,
        'role': 'user',
        'content': '无附件',
      });
      expect(legacy.attachments, isEmpty);
    });

    test('sanitize 截断到 maxChatAttachments', () {
      final refs = List.generate(
        6,
        (i) => ImageRef(type: ImageRefType.file, src: 'f$i'),
      );
      final msg = ChatMessage(
        id: 'm',
        createdAt: 1,
        role: ChatRole.user,
        content: '',
        attachments: refs,
      );
      final sanitized = sanitizeChatMessage(msg);
      expect(sanitized.attachments, hasLength(maxChatAttachments));
    });
  });

  group('persist + delete', () {
    late ChatSessionRepository repo;
    late MemoryImageAssetStore store;

    setUp(() async {
      store = MemoryImageAssetStore();
      repo = ChatSessionRepository(
        storage: MemoryChatSessionStorage(),
        attachmentStore: store,
      );
      await repo.load();
    });

    test('persistAttachments + recall 删盘', () async {
      final sid = repo.activeId;
      final refs = await repo.persistAttachments('msg_att', [_tinyPng]);
      expect(refs, hasLength(1));
      expect(refs.single.type, ImageRefType.file);
      expect(store.entries, isNotEmpty);

      await repo.appendMessage(
        sid,
        role: ChatRole.user,
        content: '',
        attachments: refs,
      );
      await repo.appendMessage(sid, role: ChatRole.assistant, content: 'ok');

      await repo.recallUserMessage(sid);
      expect(store.entries, isEmpty);
      expect(repo.activeSession!.messages, isEmpty);
    });

    test('removeSession / clearMessages 删盘', () async {
      final sid = repo.activeId;
      final refs = await repo.persistAttachments('msg2', [_tinyPng, _tinyPng]);
      await repo.appendMessage(
        sid,
        role: ChatRole.user,
        content: 'x',
        attachments: refs,
      );
      expect(store.entries.length, 2);

      await repo.clearMessages(sid);
      expect(store.entries, isEmpty);

      final refs2 = await repo.persistAttachments('msg3', [_tinyPng]);
      await repo.appendMessage(
        sid,
        role: ChatRole.user,
        content: 'y',
        attachments: refs2,
      );
      await repo.removeSession(sid);
      expect(store.entries, isEmpty);
    });

    test('超限字节拒绝落盘', () async {
      final huge = Uint8List(maxChatAttachmentBytes + 1);
      final refs = await repo.persistAttachments('big', [huge]);
      expect(refs, isEmpty);
    });
  });

  group('buildApiMessages multimodal', () {
    test('无附件仍为 string content', () {
      final history = [
        ChatMessage(
          id: 'u1',
          createdAt: 1,
          role: ChatRole.user,
          content: 'hi',
        ),
        ChatMessage(
          id: 'a1',
          createdAt: 2,
          role: ChatRole.assistant,
          content: 'yo',
        ),
      ];
      final api = buildApiMessages(history: history, systemPrompt: '规则');
      expect(api.first['content'], '规则');
      expect(api[1]['content'], 'hi');
      expect(api[1]['content'], isA<String>());
    });

    test('有附图 → parts + data URL', () {
      final history = [
        ChatMessage(
          id: 'u1',
          createdAt: 1,
          role: ChatRole.user,
          content: '描述',
          attachments: const [
            ImageRef(type: ImageRefType.file, src: 'memory://x'),
          ],
        ),
      ];
      final api = buildApiMessages(
        history: history,
        attachmentDataUrls: {
          'u1': ['data:image/png;base64,abc'],
        },
      );
      final content = api.single['content'];
      expect(content, isA<List>());
      final parts = content as List;
      expect(parts.length, 2);
      expect(parts[0]['type'], 'text');
      expect(parts[1]['type'], 'image_url');
      expect(parts[1]['image_url']['url'], 'data:image/png;base64,abc');
    });

    test('有图空文仅 image parts', () {
      final history = [
        ChatMessage(
          id: 'u1',
          createdAt: 1,
          role: ChatRole.user,
          content: '',
          attachments: const [
            ImageRef(type: ImageRefType.file, src: 'x'),
          ],
        ),
      ];
      final api = buildApiMessages(
        history: history,
        attachmentDataUrls: {
          'u1': ['data:image/jpeg;base64,zz'],
        },
      );
      final parts = api.single['content'] as List;
      expect(parts.length, 1);
      expect(parts.single['type'], 'image_url');
    });
  });

  group('canSendChatMessage attachments', () {
    test('有附图可空文；无附图需正文', () {
      final rt = GenerationRuntime();
      expect(
        canSendChatMessage(
          generation: rt,
          activeSessionId: 's',
          hasConfiguredChatProvider: true,
          textDraft: '',
          hasAttachments: true,
        ),
        isTrue,
      );
      expect(
        canSendChatMessage(
          generation: rt,
          activeSessionId: 's',
          hasConfiguredChatProvider: true,
          textDraft: '',
          hasAttachments: false,
        ),
        isFalse,
      );
      expect(
        canSendChatMessage(
          generation: rt,
          activeSessionId: 's',
          hasConfiguredChatProvider: true,
        ),
        isTrue,
      );
    });
  });

  group('facade vision gate + replaceAll cleanup', () {
    late ProviderRepository providers;
    late ChatSessionRepository sessions;
    late MemoryImageAssetStore store;
    late ChatDefaultsRepository chatDefaults;
    late ChatSessionFacade facade;

    setUp(() async {
      store = MemoryImageAssetStore();
      providers = ProviderRepository(
        storage: MemoryProviderStorage(),
        connectionTester: StubProviderConnectionTester(),
      );
      await providers.load();
      sessions = ChatSessionRepository(
        storage: MemoryChatSessionStorage(),
        attachmentStore: store,
      );
      await sessions.load();
      chatDefaults = ChatDefaultsRepository(
        storage: MemoryChatDefaultsStorage(),
      );
      await chatDefaults.load();
      facade = ChatSessionFacade(
        providers: providers,
        sessions: sessions,
        chatDefaults: chatDefaults,
        generation: GenerationRuntime(),
      );
    });

    tearDown(() {
      facade.dispose();
    });

    test('非 vision 模型带图发送失败且不落盘', () async {
      await providers.updateProvider(
        providers.activeProviderId,
        baseUrl: 'https://api.example.local/v1',
        apiKey: 'sk-test',
        chatModel: 'gpt-3.5-turbo',
      );
      expect(facade.activeChatSupportsVision, isFalse);

      String? banner;
      await facade.send(
        '看图',
        onNotify: () {},
        onBanner: (m) => banner = m,
        attachmentBytes: [_tinyPng],
      );

      expect(banner, contains('不支持图片'));
      expect(sessions.activeSession!.messages, isEmpty);
      expect(store.entries, isEmpty);
    });

    test('replaceAll / clearAllSessions 清附件盘', () async {
      final sid = sessions.activeId;
      final refs = await sessions.persistAttachments('msg_r', [_tinyPng]);
      await sessions.appendMessage(
        sid,
        role: ChatRole.user,
        content: 'x',
        attachments: refs,
      );
      expect(store.entries, isNotEmpty);

      await sessions.replaceAll(
        ChatStoreSnapshot(sessions: const [], activeId: ''),
      );
      expect(store.entries, isEmpty);

      final refs2 = await sessions.persistAttachments('msg_c', [_tinyPng]);
      await sessions.appendMessage(
        sessions.activeId,
        role: ChatRole.user,
        content: 'y',
        attachments: refs2,
      );
      expect(store.entries, isNotEmpty);

      await sessions.clearAllSessions();
      expect(store.entries, isEmpty);
    });
  });
}
