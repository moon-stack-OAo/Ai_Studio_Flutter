import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ControlledClient extends OpenAiCompatibleChatClient {
  final started = Completer<void>();
  final result = Completer<ChatStreamResult>();
  late void Function(String) emit;

  @override
  Future<ChatStreamResult> streamChatWithCredentials(
    ActiveChatCredentials credentials, {
    required List<Map<String, dynamic>> messages,
    void Function(String, String)? onDelta,
    void Function(String)? onContentDelta,
    double temperature = defaultChatTemperature,
    int? maxTokens,
    List<Map<String, dynamic>>? tools,
    Object? toolChoice,
    Duration? timeout,
    http.Client? client,
  }) {
    emit = onContentDelta!;
    started.complete();
    return result.future;
  }
}

class _RecordingStorage extends MemoryChatSessionStorage {
  final writes = <ChatStoreSnapshot>[];
  bool failWrites = false;

  @override
  Future<void> save(ChatStoreSnapshot snapshot) async {
    if (failWrites) throw StateError('disk full');
    writes.add(snapshot);
    await super.save(snapshot);
  }
}

class _SlowStorage extends MemoryChatSessionStorage {
  bool blocked = false;
  final snapshots = <ChatStoreSnapshot>[];
  final gates = <Completer<void>>[];

  @override
  Future<void> save(ChatStoreSnapshot snapshot) async {
    if (blocked) {
      snapshots.add(snapshot);
      final gate = Completer<void>();
      gates.add(gate);
      await gate.future;
    }
    await super.save(snapshot);
  }
}

ChatStoreSnapshot _snapshot(String id) =>
    ChatStoreSnapshot(sessions: const [], activeId: id);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('repository 对慢存储的并发修改只写在途和最新快照', () async {
    final storage = _SlowStorage();
    final repository = ChatSessionRepository(storage: storage);
    await repository.load();
    storage.blocked = true;
    final first = repository.renameSession(repository.activeId, 'first');
    await Future<void>.delayed(Duration.zero);
    final middle = repository.renameSession(repository.activeId, 'middle');
    final last = repository.renameSession(repository.activeId, 'last');
    expect(storage.snapshots, hasLength(1));
    storage.gates.first.complete();
    await first;
    await Future<void>.delayed(Duration.zero);
    expect(storage.snapshots, hasLength(2));
    expect(storage.snapshots.last.sessions.single.title, 'last');
    storage.gates.last.complete();
    await Future.wait([middle, last]);
    expect((await storage.load()).sessions.single.title, 'last');
    repository.dispose();
  });

  test('慢写入串行且合并最新快照；等待者按实际写入完成', () async {
    final snapshots = <ChatStoreSnapshot>[];
    final gates = <Completer<void>>[];
    var active = 0;
    var maxActive = 0;
    final writer = ChatSnapshotWriter((snapshot) async {
      snapshots.add(snapshot);
      final gate = Completer<void>();
      gates.add(gate);
      active++;
      if (active > maxActive) maxActive = active;
      await gate.future;
      active--;
    });
    final first = writer.save(_snapshot('first'));
    await Future<void>.delayed(Duration.zero);
    var mergedCompleted = false;
    final middle = writer
        .save(_snapshot('middle'))
        .then((_) => mergedCompleted = true);
    final last = writer.save(_snapshot('last'));
    expect(snapshots.map((s) => s.activeId), ['first']);
    gates.first.complete();
    await first;
    await Future<void>.delayed(Duration.zero);
    expect(mergedCompleted, isFalse);
    expect(snapshots.map((s) => s.activeId), ['first', 'last']);
    gates.last.complete();
    await Future.wait([middle, last]);
    expect(mergedCompleted, isTrue);
    expect(maxActive, 1);
  });

  test('失败传播给该批所有等待者，后续最新写入仍可成功', () async {
    final gates = <Completer<void>>[];
    final saved = <String>[];
    final writer = ChatSnapshotWriter((snapshot) async {
      final gate = Completer<void>();
      gates.add(gate);
      await gate.future;
      saved.add(snapshot.activeId);
    });
    final first = writer.save(_snapshot('first'));
    final merged = writer.save(_snapshot('merged'));
    final failure1 = expectLater(first, throwsStateError);
    final failure2 = expectLater(merged, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    final last = writer.save(_snapshot('last'));
    gates.first.completeError(StateError('disk full'));
    await Future.wait([failure1, failure2]);
    await Future<void>.delayed(Duration.zero);
    gates.last.complete();
    await last;
    expect(saved, ['last']);
  });

  test('大型快照后台编码可发送，连续 save 最终保存最新正文', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = PrefsChatSessionStorage(prefs: prefs);
    ChatStoreSnapshot snapshot(String text) => ChatStoreSnapshot(
      sessions: [
        ChatSession(
          id: 's',
          title: 't',
          createdAt: 1,
          updatedAt: 1,
          messages: [
            ChatMessage(
              id: 'm',
              createdAt: 1,
              role: ChatRole.assistant,
              content: text,
              toolCalls: const [
                ChatToolCall(id: 'c', name: 'tool', arguments: '{}'),
              ],
              appliedSkills: const [
                SkillSnapshot(id: 'skill', name: '技能', rules: '规则'),
              ],
            ),
          ],
        ),
      ],
      activeId: 's',
    );
    final text = List.filled(35000, '文本').join();
    await Future.wait([
      storage.save(snapshot(text)),
      storage.save(snapshot('$text尾')),
    ]);
    final restored = await storage.load();
    expect(restored.sessions.single.messages.single.content, '$text尾');
    expect(
      restored.sessions.single.messages.single.appliedSkills.single.rules,
      '规则',
    );
  });

  group('facade 合批和终态', () {
    late ProviderRepository providers;
    late ChatSessionRepository sessions;
    late ChatDefaultsRepository defaults;
    late GenerationRuntime generation;
    late _RecordingStorage storage;
    late _ControlledClient client;
    late ChatSessionFacade facade;

    setUp(() async {
      providers = ProviderRepository(
        storage: MemoryProviderStorage(),
        connectionTester: StubProviderConnectionTester(),
      );
      await providers.load();
      await providers.updateProvider(
        providers.activeProviderId,
        baseUrl: 'https://example.com/v1',
        apiKey: 'test',
        chatModel: 'gpt-4o',
      );
      storage = _RecordingStorage();
      sessions = ChatSessionRepository(storage: storage);
      await sessions.load();
      defaults = ChatDefaultsRepository(storage: MemoryChatDefaultsStorage());
      await defaults.load();
      generation = GenerationRuntime();
      client = _ControlledClient();
      facade = ChatSessionFacade(
        providers: providers,
        sessions: sessions,
        chatDefaults: defaults,
        generation: generation,
        chatClient: client,
        createHttpClient: () => MockClient((_) async => http.Response('', 200)),
      );
    });

    tearDown(() {
      facade.dispose();
      sessions.dispose();
      providers.dispose();
      defaults.dispose();
      generation.dispose();
    });

    test('1000 个 burst delta 只复制一次会话，首段即时，完成保留尾部', () async {
      final send = facade.send('hello', onNotify: () {});
      await client.started.future;
      final before = storage.writes.length;
      final versions = Set<List<ChatMessage>>.identity();
      for (var i = 0; i < 1000; i++) {
        client.emit('x');
        versions.add(sessions.activeSession!.messages);
      }
      expect(versions, hasLength(1));
      expect(sessions.activeSession!.messages.last.content, 'x');
      expect(storage.writes.length, before);
      final full = List.filled(1000, 'x').join();
      client.result.complete(ChatStreamResult(content: full));
      await send;
      expect(sessions.activeSession!.messages.last.content, full);
      expect(sessions.activeSession!.messages.last.streaming, isFalse);
      expect(storage.writes.length, before + 1);
      client.emit('迟到回调');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(sessions.activeSession!.messages.last.content, full);
      expect(sessions.activeSession!.messages.last.streaming, isFalse);
      expect(generation.busy, isFalse);
    });

    test('最终落盘失败仍释放生成门闩，且保留正文和错误终态', () async {
      final send = facade.send('hello', onNotify: () {});
      await client.started.future;
      client.emit('首段');
      client.emit('尾部');
      storage.failWrites = true;
      final failure = expectLater(send, throwsStateError);
      client.result.complete(const ChatStreamResult(content: '首段尾部'));
      await failure;
      expect(generation.busy, isFalse);
      expect(sessions.activeSession!.messages.last.content, '首段尾部');
      expect(sessions.activeSession!.messages.last.streaming, isFalse);
      expect(sessions.activeSession!.messages.last.error, isTrue);
    });

    for (final terminal in ['stop', 'error', 'dispose']) {
      test('$terminal 冲刷尾部且拒绝迟到 flush', () async {
        var notifications = 0;
        final send = facade.send('hello', onNotify: () => notifications++);
        await client.started.future;
        client.emit('首段');
        client.emit('缓冲尾部');
        if (terminal == 'stop') facade.stop();
        if (terminal == 'dispose') facade.dispose();
        final count = notifications;
        if (terminal == 'error') {
          client.result.completeError(const ChatApiException('模拟错误'));
        } else {
          client.emit('迟到正文');
          client.result.complete(const ChatStreamResult(content: '不能覆盖已取消正文'));
        }
        await send;
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final message = sessions.activeSession!.messages.last;
        expect(message.content, '首段缓冲尾部');
        expect(message.streaming, isFalse);
        expect(message.error, terminal == 'error');
        expect(message.stopped, terminal != 'error');
        expect(
          (await storage.load()).sessions.first.messages.last.content,
          message.content,
        );
        if (terminal == 'dispose') expect(notifications, count);
        expect(generation.busy, isFalse);
      });
    }

    test('持续流式每两秒检查点，64ms窗口仅一次更新，最终立即落盘', () async {
      final send = facade.send('hello', onNotify: () {});
      await client.started.future;
      final before = storage.writes.length;
      client.emit('a');
      client.emit('b');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(sessions.activeSession!.messages.last.content, 'ab');
      expect(storage.writes.length, before);
      await Future<void>.delayed(const Duration(milliseconds: 2000));
      client.emit('c');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(storage.writes.length, before + 1);
      client.emit('d');
      client.result.complete(const ChatStreamResult(content: 'abcd'));
      await send;
      expect(storage.writes.last.sessions.first.messages.last.content, 'abcd');
      expect(
        storage.writes.last.sessions.first.messages.last.streaming,
        isFalse,
      );
    });
  });
}
