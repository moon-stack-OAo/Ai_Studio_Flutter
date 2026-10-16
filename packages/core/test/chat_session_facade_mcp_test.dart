import 'dart:async';
import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeMcpSession implements McpSession {
  _FakeMcpSession(this.server);

  @override
  final McpServerConfig server;
  final calls = <String>[];

  @override
  Future<McpProbeResult> probe({Duration? timeout}) async =>
      const McpProbeResult(ok: true);

  @override
  Future<List<McpToolDescriptor>> listTools({
    Duration? timeout,
    bool forceRefresh = false,
  }) async => server.toolsCache;

  @override
  Future<McpToolCallResult> callTool(
    McpToolCallRequest request, {
    Duration? timeout,
    bool Function()? isCancelled,
  }) async {
    calls.add(request.toolName);
    return McpToolCallResult(
      toolCallId: request.toolCallId,
      status: McpToolCallStatus.success,
      content: 'tool-ok:${request.toolName}',
    );
  }

  @override
  void close() {}
}

class _FakeFactory implements McpSessionFactory {
  _FakeFactory(this.sessions);

  final Map<String, _FakeMcpSession> sessions;

  @override
  McpSession create(
    McpServerConfig server, {
    McpAuthProvider? auth,
    ProcessHost? processHost,
  }) {
    return sessions.putIfAbsent(server.id, () => _FakeMcpSession(server));
  }
}

void main() {
  late ProviderRepository providers;
  late ChatSessionRepository sessions;
  late ChatDefaultsRepository chatDefaults;
  late GenerationRuntime generation;

  setUp(() async {
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
    );
    sessions = ChatSessionRepository(storage: MemoryChatSessionStorage());
    await sessions.load();
    chatDefaults = ChatDefaultsRepository(storage: MemoryChatDefaultsStorage());
    await chatDefaults.load();
    generation = GenerationRuntime();
  });

  test('无 MCP 注入时路径不变（仅文本流）', () async {
    final client = MockClient.streaming((request, bodyStream) async {
      await bodyStream.drain();
      return http.StreamedResponse(
        Stream.value(
          utf8.encode(
            'data: {"choices":[{"delta":{"content":"嗨"}}]}\n'
            'data: [DONE]\n',
          ),
        ),
        200,
      );
    });
    final facade = ChatSessionFacade(
      providers: providers,
      sessions: sessions,
      chatDefaults: chatDefaults,
      generation: generation,
      chatClient: OpenAiCompatibleChatClient(client: client),
      createHttpClient: () => createSafeHttpClient(inner: client),
    );
    await facade.send('你好', onNotify: () {});
    final msgs = sessions.activeSession!.messages;
    expect(msgs, hasLength(2));
    expect(msgs.last.role, ChatRole.assistant);
    expect(msgs.last.content, '嗨');
    expect(msgs.last.hasToolCalls, isFalse);
    facade.dispose();
  });

  test('有 tool_calls 时串行 call 并回灌再生成', () async {
    final skills = SkillRepository(
      storage: MemorySkillStorage([
        const CustomSkill(
          id: 'chat-skill',
          name: '对话约束',
          rules: '旧规则',
          targets: {SkillTarget.chat},
        ),
      ]),
    );
    await skills.load();
    await chatDefaults.update(systemPrompt: '全局规则');
    await sessions.setSessionOverrides(
      sessions.activeId,
      const ChatOverrides(systemPrompt: '会话规则'),
    );
    var round = 0;
    final client = MockClient.streaming((request, bodyStream) async {
      final body = jsonDecode(await bodyStream.bytesToString()) as Map;
      round++;
      final system = (body['messages'] as List).first['content'] as String;
      expect(system, startsWith('会话规则'));
      expect(system, contains('旧规则'));
      expect(system, isNot(contains('全局规则')));
      expect(system, isNot(contains('新规则')));
      if (round == 1) {
        await skills.saveSkill(skills.skills.single.copyWith(rules: '新规则'));
        expect(body['tools'], isA<List>());
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(
              'data: {"choices":[{"delta":{"content":"准备"}}]}\n'
              'data: {"choices":[{"delta":{"content":"调用工具"}}]}\n'
              'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"biz.query","arguments":"{}"}}]},"finish_reason":"tool_calls"}]}\n'
              'data: [DONE]\n',
            ),
          ),
          200,
        );
      }
      // 第二轮：应含 role=tool
      final messages = body['messages'] as List;
      expect(messages.any((m) => m is Map && m['role'] == 'tool'), isTrue);
      return http.StreamedResponse(
        Stream.value(
          utf8.encode(
            'data: {"choices":[{"delta":{"content":"根据工具：完成"}}]}\n'
            'data: [DONE]\n',
          ),
        ),
        200,
      );
    });

    final mcpRepo = McpServerRepository(
      storage: MemoryMcpServerStorage([
        const McpServerConfig(
          id: 'mcp_1',
          displayName: 'Biz',
          baseUrl: 'https://mcp.example.local/mcp',
          toolsCache: [
            McpToolDescriptor(
              name: 'biz.query',
              sideEffect: McpToolSideEffect.read,
            ),
          ],
        ),
      ]),
    );
    await mcpRepo.load();

    final fakeSessions = <String, _FakeMcpSession>{};
    final facade = ChatSessionFacade(
      providers: providers,
      sessions: sessions,
      chatDefaults: chatDefaults,
      generation: generation,
      chatClient: OpenAiCompatibleChatClient(client: client),
      createHttpClient: () => createSafeHttpClient(inner: client),
      mcpServers: mcpRepo,
      mcpSessionFactory: _FakeFactory(fakeSessions),
      skillRepository: skills,
      toolAuthPrompter: allowAllToolAuthPrompter,
    );

    await facade.send('查一下', onNotify: () {});
    final msgs = sessions.activeSession!.messages;
    // user + assistant(tool_calls) + tool + assistant(final)
    expect(msgs.length, greaterThanOrEqualTo(4));
    expect(msgs[0].role, ChatRole.user);
    expect(msgs[0].appliedSkills.single.rules, '旧规则');
    expect(msgs[1].role, ChatRole.assistant);
    expect(msgs[1].hasToolCalls, isTrue);
    expect(msgs[1].content, '准备调用工具');
    expect(msgs[1].streaming, isFalse);
    expect(msgs[2].role, ChatRole.tool);
    expect(msgs[2].content, contains('tool-ok'));
    expect(msgs.last.role, ChatRole.assistant);
    expect(msgs.last.content, contains('完成'));
    expect(fakeSessions['mcp_1']!.calls, ['biz.query']);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(sessions.activeSession!.messages[1].streaming, isFalse);
    expect(sessions.activeSession!.messages.last.content, '根据工具：完成');
    facade.dispose();
  });

  test('用户拒绝授权：回灌拒绝且不 call Server', () async {
    var round = 0;
    final client = MockClient.streaming((request, bodyStream) async {
      await bodyStream.drain();
      round++;
      if (round == 1) {
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(
              'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","type":"function","function":{"name":"biz.write","arguments":"{}"}}]},"finish_reason":"tool_calls"}]}\n'
              'data: [DONE]\n',
            ),
          ),
          200,
        );
      }
      return http.StreamedResponse(
        Stream.value(
          utf8.encode(
            'data: {"choices":[{"delta":{"content":"好的，已跳过"}}]}\n'
            'data: [DONE]\n',
          ),
        ),
        200,
      );
    });

    final mcpRepo = McpServerRepository(
      storage: MemoryMcpServerStorage([
        const McpServerConfig(
          id: 'mcp_1',
          displayName: 'Biz',
          baseUrl: 'https://mcp.example.local/mcp',
          toolsCache: [
            McpToolDescriptor(
              name: 'biz.write',
              sideEffect: McpToolSideEffect.write,
            ),
          ],
        ),
      ]),
    );
    await mcpRepo.load();
    final fakeSessions = <String, _FakeMcpSession>{};
    final facade = ChatSessionFacade(
      providers: providers,
      sessions: sessions,
      chatDefaults: chatDefaults,
      generation: generation,
      chatClient: OpenAiCompatibleChatClient(client: client),
      createHttpClient: () => createSafeHttpClient(inner: client),
      mcpServers: mcpRepo,
      mcpSessionFactory: _FakeFactory(fakeSessions),
      toolAuthPrompter: denyAllToolAuthPrompter,
    );
    await facade.send('写入', onNotify: () {});
    expect(fakeSessions['mcp_1']?.calls ?? [], isEmpty);
    final toolMsg = sessions.activeSession!.messages.firstWhere(
      (m) => m.role == ChatRole.tool,
    );
    expect(toolMsg.content, contains('拒绝'));
    facade.dispose();
  });

  test(
    'confirm_once is isolated by chat and revoked on server or credential changes',
    () async {
      var round = 0;
      final client = MockClient.streaming((request, bodyStream) async {
        await bodyStream.drain();
        final payload = ++round % 2 == 1
            ? '{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c$round","type":"function","function":{"name":"biz.write","arguments":"{}"}}]},"finish_reason":"tool_calls"}]}'
            : '{"choices":[{"delta":{"content":"done"}}]}';
        return http.StreamedResponse(
          Stream.value(utf8.encode('data: $payload\n\ndata: [DONE]\n\n')),
          200,
        );
      });
      final repo = McpServerRepository(
        storage: MemoryMcpServerStorage([
          const McpServerConfig(
            id: 's',
            displayName: 'Server',
            baseUrl: 'https://example.com/mcp',
            defaultToolPolicy: McpToolPolicyLevel.confirmOnce,
            toolsCache: [
              McpToolDescriptor(
                name: 'biz.write',
                sideEffect: McpToolSideEffect.write,
              ),
            ],
          ),
        ]),
        secretStore: MemorySecretStore(),
      );
      await repo.load();
      var prompts = 0;
      final facade = ChatSessionFacade(
        providers: providers,
        sessions: sessions,
        chatDefaults: chatDefaults,
        generation: generation,
        chatClient: OpenAiCompatibleChatClient(client: client),
        createHttpClient: () => createSafeHttpClient(inner: client),
        mcpServers: repo,
        mcpSessionFactory: _FakeFactory({}),
        toolAuthPrompter: (_) async {
          prompts++;
          return true;
        },
      );
      addTearDown(facade.dispose);
      final firstId = sessions.activeId;
      await facade.send('a1', onNotify: () {});
      await facade.send('a2', onNotify: () {});
      expect(prompts, 1);
      await sessions.createSession();
      await facade.send('b1', onNotify: () {});
      await facade.send('b2', onNotify: () {});
      expect(prompts, 2);
      await sessions.setActive(firstId);
      await facade.send('a3', onNotify: () {});
      expect(prompts, 2);
      await repo.update(
        repo
            .findById('s')!
            .copyWith(baseUrl: 'https://changed.example.com/mcp'),
      );
      await facade.send('a4', onNotify: () {});
      expect(prompts, 3);
      await repo.writeBearerSecret('s', 'test-token-1');
      await facade.send('a5', onNotify: () {});
      expect(prompts, 4);
      await repo.writeBearerSecret('s', 'test-token-2');
      await facade.send('a6', onNotify: () {});
      expect(prompts, 5);
    },
  );
}
