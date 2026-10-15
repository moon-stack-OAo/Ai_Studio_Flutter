import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;

const _skill = CustomSkill(
  id: 's',
  name: '约束',
  prompt: '限定场景',
  rules: '黑白',
  targets: {SkillTarget.chat, SkillTarget.image, SkillTarget.video},
);

class _GateChatStorage extends MemoryChatSessionStorage {
  final gate = Completer<void>();
  @override
  Future<void> save(ChatStoreSnapshot snapshot) async {
    await gate.future;
    await super.save(snapshot);
  }
}

class _GateImageStorage extends MemoryImageSessionStorage {
  final gate = Completer<void>();
  @override
  Future<void> save(ImageStoreSnapshot snapshot) async {
    await gate.future;
    await super.save(snapshot);
  }
}

class _GateVideoStorage extends MemoryVideoSessionStorage {
  final gate = Completer<void>();
  @override
  Future<void> save(VideoStoreSnapshot snapshot) async {
    await gate.future;
    await super.save(snapshot);
  }
}

http.StreamedResponse _chatResponse() => http.StreamedResponse(
  Stream.value(
    utf8.encode(
      'data: {"choices":[{"delta":{"content":"完成"}}]}\n\ndata: [DONE]\n\n',
    ),
  ),
  200,
);

void main() {
  late ProviderRepository providers;
  late SkillRepository skills;

  setUp(() async {
    providers = ProviderRepository(
      storage: MemoryProviderStorage(),
      connectionTester: StubProviderConnectionTester(),
    );
    await providers.load();
    await providers.updateProvider(
      providers.activeProviderId,
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'test',
      chatModel: 'gpt-4o',
      imageModel: 'gpt-image-1',
      videoModel: 'sora-2',
    );
    skills = SkillRepository(storage: MemorySkillStorage([_skill]));
    await skills.load();
  });

  test('chat 首个 await 前捕获技能，global system 追加，消息更新和存储保留快照', () async {
    final storage = _GateChatStorage();
    final sessions = ChatSessionRepository(storage: storage);
    final defaults = ChatDefaultsRepository(
      storage: MemoryChatDefaultsStorage(),
    );
    await defaults.load();
    await defaults.update(systemPrompt: '全局规则');
    var requests = 0;
    final client = MockClient.streaming((request, body) async {
      requests++;
      final messages =
          (jsonDecode(await body.bytesToString()) as Map)['messages'] as List;
      expect(
        messages.first['content'],
        composeChatSystemPrompt('全局规则', [
          const SkillSnapshot(id: 's', name: '约束', prompt: '限定场景', rules: '黑白'),
        ]),
      );
      expect(messages.last['content'], '猫');
      return _chatResponse();
    });
    final facade = ChatSessionFacade(
      providers: providers,
      sessions: sessions,
      chatDefaults: defaults,
      generation: GenerationRuntime(),
      skillRepository: skills,
      chatClient: OpenAiCompatibleChatClient(client: client),
      createHttpClient: () => client,
    );
    final sending = facade.send('猫', onNotify: () {});
    await skills.clear();
    storage.gate.complete();
    await sending;
    expect(requests, 1);
    final message = sessions.activeSession!.messages.first;
    expect(message.appliedSkills.single.rules, '黑白');
    await sessions.updateMessage(
      sessions.activeId,
      message.id,
      content: '更新正文',
    );
    expect(
      (await storage.load())
          .sessions
          .first
          .messages
          .first
          .appliedSkills
          .single
          .rules,
      '黑白',
    );
    facade.dispose();
  });

  for (final edit in [false, true]) {
    test('image ${edit ? "图生" : "文生"} 实际注入，首次 await 前快照固定，原文可重跑', () async {
      final storage = _GateImageStorage();
      final sessions = ImageSessionRepository(storage: storage);
      final expected = composeSkillPrompt(
        prompt: '猫',
        skills: skills.snapshotFor(SkillTarget.image),
      );
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        if (edit) {
          expect(request.url.path, endsWith('/images/edits'));
          expect(
            utf8.decode(request.bodyBytes, allowMalformed: true),
            contains(expected),
          );
        } else {
          expect((jsonDecode(request.body) as Map)['prompt'], expected);
        }
        return http.Response(
          jsonEncode({
            'data': [
              {'url': 'https://cdn.example/cat.png'},
            ],
          }),
          200,
        );
      });
      final facade = ImageSessionFacade(
        providers: providers,
        sessions: sessions,
        generation: GenerationRuntime(),
        skillRepository: skills,
        imageClient: OpenAiCompatibleImageClient(client: client),
        createHttpClient: () => client,
      );
      final sending = facade.generate(
        prompt: '猫',
        imageBytes: edit ? Uint8List.fromList([1, 2, 3]) : null,
        onNotify: () {},
      );
      await skills.saveSkill(_skill.copyWith(prompt: '改变后的技能'));
      storage.gate.complete();
      await sending;
      expect(requests, 1);
      final item = sessions.activeSession!.items.single;
      expect(item.status, ImageItemStatus.done);
      expect(item.prompt, '猫');
      expect(item.finalPrompt, expected);
      expect(item.appliedSkills.single.prompt, '限定场景');
      expect(
        (await storage.load()).sessions.first.items.single.finalPrompt,
        expected,
      );
      facade.dispose();
    });

    for (final prompt in edit ? ['猫', ''] : ['猫']) {
      test(
        'video ${edit ? "图生" : "文生"} prompt=$prompt 实际注入，快照固定，完成/进度更新保留字段',
        () async {
          final storage = _GateVideoStorage();
          final sessions = VideoSessionRepository(storage: storage);
          final expected = composeSkillPrompt(
            prompt: prompt,
            skills: skills.snapshotFor(SkillTarget.video),
          ).trim();
          var posts = 0;
          final client = MockClient((request) async {
            if (request.method == 'POST') {
              posts++;
              if (edit) {
                expect(
                  utf8.decode(request.bodyBytes, allowMalformed: true),
                  contains(expected),
                );
              } else {
                expect((jsonDecode(request.body) as Map)['prompt'], expected);
              }
              return http.Response(
                jsonEncode({'id': 'job', 'status': 'queued'}),
                200,
              );
            }
            return http.Response(
              jsonEncode({
                'id': 'job',
                'status': 'completed',
                'url': 'https://cdn.example/cat.mp4',
              }),
              200,
            );
          });
          final facade = VideoJobFacade(
            providers: providers,
            sessions: sessions,
            generation: GenerationRuntime(),
            skillRepository: skills,
            videoClient: OpenAiCompatibleVideoClient(
              client: client,
              pollInterval: Duration.zero,
            ),
            createHttpClient: () => client,
          );
          final bytes = edit
              ? Uint8List.fromList(
                  img.encodePng(img.Image(width: 2, height: 2)),
                )
              : null;
          final sending = facade.generate(
            prompt: prompt,
            imageBytes: bytes,
            onNotify: () {},
          );
          await skills.clear();
          storage.gate.complete();
          await sending;
          expect(posts, 1);
          final item = sessions.activeSession!.items.single;
          expect(
            item.status,
            VideoItemStatus.success,
            reason: item.errorMessage,
          );
          expect(item.prompt, prompt);
          expect(item.finalPrompt, expected);
          expect(item.appliedSkills.single.rules, '黑白');
          expect(
            (await storage.load()).sessions.first.items.single.finalPrompt,
            expected,
          );
          facade.dispose();
        },
      );
    }
  }

  test('润色和迭代只用传入约束，优先于内置风格，正文不拼技能区块', () async {
    const constraints = [
      SkillSnapshot(id: 'image', name: '图像技能', rules: '仅绿色'),
    ];
    var requests = 0;
    final client = MockClient.streaming((request, body) async {
      requests++;
      final messages =
          (jsonDecode(await body.bytesToString()) as Map)['messages'] as List;
      final system = messages.first['content'] as String;
      expect(system, contains('仅绿色'));
      expect(system, contains('优先于内置润色风格'));
      expect(system, contains('不要复制技能区块'));
      expect(system, isNot(contains('黑白')));
      expect(messages.last['content'], isNot(contains('【技能：')));
      return _chatResponse();
    });
    final chatClient = OpenAiCompatibleChatClient(client: client);
    expect(
      await enhancePrompt(
        text: '猫',
        domain: PromptDomain.image,
        credentials: providers.activeChatCredentials!,
        chatClient: chatClient,
        customSkills: constraints,
      ),
      '完成',
    );
    expect(
      await refineEnhancedPrompt(
        previous: '猫',
        instruction: '更精简',
        domain: PromptDomain.video,
        credentials: providers.activeChatCredentials!,
        chatClient: chatClient,
        customSkills: constraints,
      ),
      '完成',
    );
    expect(requests, 2);
    expect(
      resolveEnhanceSystemPrompt(PromptDomain.image, null),
      isNot(contains('【技能：')),
    );
    chatClient.close();
  });
}
