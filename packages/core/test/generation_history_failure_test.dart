import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Files extends HistoryFileAccess {
  final values = <String, String>{};
  String? failWrite;
  @override
  Future<String?> read(String path) async => values[path];
  @override
  Future<void> write(String path, String value) async {
    if (failWrite != null && path.endsWith(failWrite!)) {
      throw const FileSystemException('injected');
    }
    values[path] = value;
  }

  @override
  Future<void> remove(String path) async => values.remove(path);
  @override
  Future<List<String>> files(String path) async => values.keys
      .where(
        (p) =>
            p.startsWith('$path/') &&
            !p.substring(path.length + 1).contains('/'),
      )
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final kind in ['image', 'video', 'chat']) {
    for (final point in ['pending.json', 'active.json']) {
      test(
        '$kind append failure at $point recovers authoritative history',
        () async {
          SharedPreferences.setMockInitialValues({});
          final prefs = await SharedPreferences.getInstance();
          final files = _Files();
          final root = Directory('generation-failure-$kind-$point');
          final dynamic repo = switch (kind) {
            'image' => ImageSessionRepository(
              storage: FileImageSessionStorage(
                root: () async => root,
                prefs: prefs,
                files: files,
              ),
            ),
            'video' => VideoSessionRepository(
              storage: FileVideoSessionStorage(
                root: () async => root,
                prefs: prefs,
                files: files,
              ),
            ),
            _ => ChatSessionRepository(
              storage: FileChatSessionStorage(
                root: () async => root,
                prefs: prefs,
                files: files,
              ),
            ),
          };
          await repo.load();
          final String id = repo.activeId;
          Future<dynamic> append(String prompt) => switch (kind) {
            'image' => repo.appendLoadingItem(
              id,
              mode: ImageGenMode.text,
              prompt: prompt,
            ),
            'video' => repo.appendLoadingItem(
              id,
              mode: VideoGenMode.text,
              prompt: prompt,
            ),
            _ => repo.appendMessage(
              id,
              role: ChatRole.assistant,
              content: prompt,
              streaming: true,
            ),
          };
          files.failWrite = point;
          await expectLater(
            append('retained'),
            throwsA(isA<HistoryStorageException>()),
          );
          expect(repo.writesBlocked, isTrue);
          final List<dynamic> before = kind == 'chat'
              ? repo.activeSession.messages
              : repo.activeSession.items;
          expect(
            kind == 'chat'
                ? before.single.streaming
                : before.single.status ==
                      (kind == 'image'
                          ? ImageItemStatus.loading
                          : VideoItemStatus.loading),
            isFalse,
          );
          files.failWrite = null;
          await repo.recoverHistory();
          final List<dynamic> restored = kind == 'chat'
              ? repo.activeSession.messages
              : repo.activeSession.items;
          expect(restored, point == 'active.json' ? hasLength(1) : isEmpty);
          if (restored.isNotEmpty) {
            expect(
              kind == 'chat'
                  ? restored.single.streaming
                  : restored.single.status ==
                        (kind == 'image'
                            ? ImageItemStatus.loading
                            : VideoItemStatus.loading),
              isFalse,
            );
          }
          await append('next');
          expect(repo.writesBlocked, isFalse);
          // A real operation must exclude recovery even after its visible
          // loading flag was cleared by a failed completion write.
          final entered = Completer<void>();
          final finish = Completer<void>();
          final List<dynamic> current = kind == 'chat'
              ? repo.activeSession.messages
              : repo.activeSession.items;
          final String itemId = current.last.id;
          Future<void> action() async {
            files.failWrite = 'pending.json';
            if (kind == 'chat') {
              await expectLater(
                repo.updateMessage(id, itemId, streaming: false),
                throwsA(isA<HistoryStorageException>()),
              );
            } else {
              await expectLater(
                repo.failItem(id, itemId, 'failed completion'),
                throwsA(isA<HistoryStorageException>()),
              );
            }
            entered.complete();
            await finish.future;
          }

          final Future<dynamic> running = kind == 'chat'
              ? repo.runGeneration(id, action, itemId: () => itemId)
              : repo.runGeneration(id, action, itemId: itemId);
          await entered.future;
          await expectLater(
            repo.recoverHistory(),
            throwsA(isA<HistoryStorageException>()),
          );
          finish.complete();
          await running;
          files.failWrite = null;
          await repo.recoverHistory();
          expect(repo.writesBlocked, isFalse);
          repo.dispose();
        },
      );
    }
  }

  for (final kind in ['chat', 'video']) {
    test(
      '$kind facade append failure never starts request and can retry',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final files = _Files();
        final providers = ProviderRepository(
          storage: MemoryProviderStorage(),
          connectionTester: StubProviderConnectionTester(),
        );
        await providers.load();
        final p = await providers.addProvider(
          name: 'test',
          baseUrl: 'https://example.com/v1',
          apiKey: 'test',
          chatModel: 'gpt-4o',
          videoModel: 'sora-2',
        );
        await providers.setActiveProvider(p.id);
        final generation = GenerationRuntime();
        final defaults = ChatDefaultsRepository(
          storage: MemoryChatDefaultsStorage(),
        );
        await defaults.load();
        final dynamic repo = kind == 'chat'
            ? ChatSessionRepository(
                storage: FileChatSessionStorage(
                  root: () async => Directory('chat-facade'),
                  prefs: prefs,
                  files: files,
                ),
              )
            : VideoSessionRepository(
                storage: FileVideoSessionStorage(
                  root: () async => Directory('video-facade'),
                  prefs: prefs,
                  files: files,
                ),
              );
        await repo.load();
        var calls = 0;
        final mock = MockClient((request) async {
          calls++;
          return kind == 'chat'
              ? http.Response(
                  'data: {"choices":[{"delta":{"content":"ok"}}]}\n\ndata: [DONE]\n\n',
                  200,
                  headers: {'content-type': 'text/event-stream'},
                )
              : http.Response(
                  '{"id":"job","status":"completed","video_url":"https://example.com/a.mp4"}',
                  200,
                );
        });
        final dynamic facade = kind == 'chat'
            ? ChatSessionFacade(
                providers: providers,
                sessions: repo,
                chatDefaults: defaults,
                generation: generation,
                chatClient: OpenAiCompatibleChatClient(client: mock),
                createHttpClient: () => mock,
              )
            : VideoJobFacade(
                providers: providers,
                sessions: repo,
                generation: generation,
                videoClient: OpenAiCompatibleVideoClient(client: mock),
                createHttpClient: () => mock,
              );
        Future<void> run() => kind == 'chat'
            ? facade.send('first', onNotify: () {})
            : facade.generate(prompt: 'first', onNotify: () {});
        files.failWrite = 'active.json';
        await expectLater(run(), throwsA(isA<HistoryStorageException>()));
        expect(calls, 0);
        expect(generation.busy, isFalse);
        files.failWrite = null;
        await repo.recoverHistory();
        await run();
        expect(calls, greaterThan(0));
        expect(generation.busy, isFalse);
        facade.dispose();
        repo.dispose();
        defaults.dispose();
        providers.dispose();
        generation.dispose();
      },
    );
  }

  for (final failDuringRequest in [false, true]) {
    test(
      'image facade failure during request=$failDuringRequest releases recovery gate',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final files = _Files();
        final sessions = ImageSessionRepository(
          storage: FileImageSessionStorage(
            root: () async => Directory('image-facade-$failDuringRequest'),
            prefs: prefs,
            files: files,
          ),
        );
        await sessions.load();
        final providers = ProviderRepository(
          storage: MemoryProviderStorage(),
          connectionTester: StubProviderConnectionTester(),
        );
        await providers.load();
        final p = await providers.addProvider(
          name: 'test',
          baseUrl: 'https://example.com/v1',
          apiKey: 'test',
          imageModel: 'gpt-image-1',
        );
        await providers.setActiveProvider(p.id);
        final generation = GenerationRuntime();
        var calls = 0;
        final entered = Completer<void>();
        final finish = Completer<void>();
        final mock = MockClient((request) async {
          calls++;
          if (failDuringRequest && calls == 1) {
            files.failWrite = 'pending.json';
            await expectLater(
              sessions.createSession(),
              throwsA(isA<HistoryStorageException>()),
            );
            entered.complete();
            await finish.future;
            throw StateError('request failed');
          }
          return http.Response(
            '{"data":[{"url":"https://example.com/a.png"}]}',
            200,
          );
        });
        final facade = ImageSessionFacade(
          providers: providers,
          sessions: sessions,
          generation: generation,
          imageClient: OpenAiCompatibleImageClient(client: mock),
          createHttpClient: () => mock,
        );
        if (!failDuringRequest) files.failWrite = 'active.json';
        final running = facade.generate(prompt: 'first', onNotify: () {});
        if (failDuringRequest) {
          await entered.future;
          expect(generation.busy, isTrue);
          await expectLater(
            sessions.recoverHistory(),
            throwsA(isA<HistoryStorageException>()),
          );
          finish.complete();
        }
        await expectLater(running, throwsA(isA<HistoryStorageException>()));
        expect(generation.busy, isFalse);
        expect(calls, failDuringRequest ? 1 : 0);
        files.failWrite = null;
        await sessions.recoverHistory();
        expect(
          sessions.activeSession!.items.single.status,
          ImageItemStatus.error,
        );
        await facade.generate(prompt: 'next', onNotify: () {});
        expect(sessions.activeSession!.items.last.status, ImageItemStatus.done);
        facade.dispose();
        generation.dispose();
        sessions.dispose();
        providers.dispose();
      },
    );
  }
}
