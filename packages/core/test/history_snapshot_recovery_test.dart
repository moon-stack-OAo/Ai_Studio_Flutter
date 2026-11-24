import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Prefs implements SharedPreferences {
  final values = <String, Object>{};
  String? failKey;
  bool throws = false;
  @override
  Object? get(String key) => values[key];
  @override
  bool containsKey(String key) => values.containsKey(key);
  @override
  Future<bool> setString(String key, String value) async {
    if (key == failKey) {
      if (throws) throw StateError('sensitive platform error');
      return false;
    }
    values[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    if (key == failKey) return false;
    values.remove(key);
    return true;
  }

  @override
  Future<void> reload() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _OptimisticPrefs extends _Prefs {
  final durable = <String, Object>{};
  bool reloadFails = true;
  @override
  Future<bool> setString(String key, String value) async {
    values[key] = value;
    if (key == failKey) return false;
    durable[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    values.remove(key);
    if (key == failKey) return false;
    durable.remove(key);
    return true;
  }

  @override
  Future<void> reload() async {
    if (reloadFails) throw StateError('private platform details');
    values
      ..clear()
      ..addAll(durable);
  }
}

String _payload(String id, String children) => jsonEncode({
  'activeId': id,
  'sessions': [
    {'id': id, children: <Object>[]},
  ],
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final kind in ['chat', 'image', 'video']) {
    final key = 'core.${kind}_sessions.v1';
    final children = kind == 'chat' ? 'messages' : 'items';
    dynamic storage(_Prefs p) => switch (kind) {
      'chat' => PrefsChatSessionStorage(prefs: p),
      'image' => PrefsImageSessionStorage(prefs: p),
      _ => PrefsVideoSessionStorage(prefs: p),
    };
    test('$kind missing and explicit empty are not corruption', () async {
      final p = _Prefs();
      final s = storage(p);
      expect((await s.load()).sessions, isEmpty);
      expect(s.recoveryState, HistoryRecoveryState.missing);
      p.values[key] = '{"sessions":[],"activeId":""}';
      expect((await s.load()).sessions, isEmpty);
      expect(s.recoveryState, HistoryRecoveryState.healthy);
    });
    for (final bad in <Object>[
      '{private-body',
      '[]',
      '{"sessions":{}}',
      '{"sessions":[{"id":"s","$children":[7]}]}',
      '{"sessions":[{"id":"s","$children":[{"id":"m","prompt":{}}]}]}',
      17,
    ]) {
      test(
        '$kind rejects malformed ${bad.runtimeType} without overwriting',
        () async {
          final p = _Prefs()..values[key] = bad;
          final s = storage(p);
          await expectLater(s.load(), throwsA(isA<HistoryStorageException>()));
          expect(p.values[key], bad);
          expect(s.writesBlocked, isTrue);
          expect(jsonDecode(p.values['$key.corrupt'] as String)['value'], bad);
          await expectLater(
            storage(p).load(),
            throwsA(isA<HistoryStorageException>()),
          );
        },
      );
    }
    test(
      '$kind recovers previous, retains exact corrupt original across restart',
      () async {
        final valid = _payload('old', children);
        final p = _Prefs()
          ..values.addAll({key: '{broken', '$key.previous': valid});
        final s = storage(p);
        expect((await s.load()).sessions.single.id, 'old');
        expect(s.recoveryState, HistoryRecoveryState.recovered);
        expect(p.values[key], valid);
        expect((await storage(p).load()).sessions.single.id, 'old');
        expect(
          jsonDecode(p.values['$key.corrupt'] as String)['value'],
          '{broken',
        );
      },
    );
    test('$kind failed quarantine prevents automatic restore', () async {
      final p = _Prefs()
        ..values.addAll({
          key: '{broken',
          '$key.previous': _payload('old', children),
        })
        ..failKey = '$key.corrupt';
      await expectLater(
        storage(p).load(),
        throwsA(isA<HistoryStorageException>()),
      );
      expect(p.values[key], '{broken');
      p.failKey = null;
      expect((await storage(p).recover()).sessions.single.id, 'old');
    });
    test('$kind older different quarantine is immutable', () async {
      final p = _Prefs()
        ..values.addAll({
          key: '{new-bad',
          '$key.previous': _payload('old', children),
          '$key.corrupt': 'older-bad',
        });
      await expectLater(
        storage(p).load(),
        throwsA(isA<HistoryStorageException>()),
      );
      expect(p.values[key], '{new-bad');
      expect(p.values['$key.corrupt'], 'older-bad');
    });
    test(
      '$kind repository starts safely and blocks mutations on corruption',
      () async {
        final p = _Prefs()..values[key] = '{private-body';
        final dynamic repo = switch (kind) {
          'chat' => ChatSessionRepository(storage: storage(p)),
          'image' => ImageSessionRepository(storage: storage(p)),
          _ => VideoSessionRepository(storage: storage(p)),
        };
        await repo.load();
        expect(repo.sessions, hasLength(1));
        expect(repo.writesBlocked, isTrue);
        await expectLater(
          repo.createSession(),
          throwsA(isA<HistoryStorageException>()),
        );
        await repo.clearAllSessions();
        expect(p.values.keys.where((k) => k.endsWith('.corrupt')), isEmpty);
        expect((await storage(p).load()).sessions, hasLength(1));
        repo.dispose();
      },
    );
  }
  for (final failed in [false, true]) {
    test(
      'chat deletion commit failed=$failed retains or cleans assets safely',
      () async {
        final p = _Prefs();
        final assets = MemoryImageAssetStore();
        final path = await assets.savePng(Uint8List.fromList([1, 2]), 'a');
        final repo = ChatSessionRepository(
          storage: PrefsChatSessionStorage(prefs: p),
          attachmentStore: assets,
        );
        await repo.load();
        await repo.appendMessage(
          repo.activeId,
          role: ChatRole.user,
          content: 'body',
          attachments: [ImageRef(type: ImageRefType.file, src: path)],
          toolCalls: const [
            ChatToolCall(id: 'call', name: 'tool', arguments: '{}'),
          ],
          appliedSkills: const [
            SkillSnapshot(id: 'skill', name: 'skill', rules: 'rules'),
          ],
        );
        // Real model roundtrip including optional nested records.
        final loaded = await PrefsChatSessionStorage(prefs: p).load();
        expect(
          loaded.sessions.single.messages.single.toolCalls.single.id,
          'call',
        );
        expect(
          loaded.sessions.single.messages.single.appliedSkills.single.id,
          'skill',
        );
        if (failed) p.failKey = 'core.chat_sessions.v1';
        if (failed) {
          await expectLater(
            repo.clearMessages(repo.activeId),
            throwsA(isA<HistoryStorageException>()),
          );
          expect(await assets.read(path), isNotNull);
        } else {
          await repo.clearMessages(repo.activeId);
          expect(await assets.read(path), isNull);
        }
        p.failKey = null;
        final restart = await PrefsChatSessionStorage(prefs: p).load();
        expect(
          restart.sessions.single.messages,
          failed ? hasLength(1) : isEmpty,
        );
        if (!failed) {
          p.values['core.chat_sessions.v1'] = 'corrupt';
          final restored = await PrefsChatSessionStorage(prefs: p).load();
          expect(restored.sessions.single.messages, isEmpty);
        }
        repo.dispose();
      },
    );
  }
  test(
    'interrupted clear retries removals without resurrecting history',
    () async {
      final p = _Prefs()
        ..values.addAll({
          'test': _payload('a', 'messages'),
          'test.previous': _payload('b', 'messages'),
          'test.corrupt': 'isolated',
        })
        ..failKey = 'test.previous';
      HistorySnapshotStore<Map<String, dynamic>> store() =>
          HistorySnapshotStore(
            key: 'test',
            prefs: () async => p,
            decode: (raw) => decodeHistoryObject(raw, 'messages'),
            empty: {},
          );
      await expectLater(
        store().clear(),
        throwsA(isA<HistoryStorageException>()),
      );
      expect(p.values['test.clearing'], isNotNull);
      p.failKey = null;
      expect(await store().load(), isEmpty);
      expect(p.values, isEmpty);
    },
  );
  test(
    'serial saves preserve immediate previous valid snapshot on restart',
    () async {
      final p = _Prefs();
      HistorySnapshotStore<Map<String, dynamic>> store() =>
          HistorySnapshotStore(
            key: 'test',
            prefs: () async => p,
            decode: (raw) => decodeHistoryObject(raw, 'messages'),
            empty: {},
          );
      final s = store();
      await s.load();
      await Future.wait([
        s.save(_payload('a', 'messages')),
        s.save(_payload('b', 'messages')),
        s.save(_payload('c', 'messages')),
      ]);
      expect(jsonDecode(p.values['test.previous'] as String)['activeId'], 'b');
      p.values['test'] = 'corrupt';
      expect((await store().load())['activeId'], 'b');
    },
  );
  for (final throws in [false, true]) {
    for (final failedKey in ['test.previous', 'test']) {
      test(
        'failed write $failedKey throw=$throws preserves original/recovery',
        () async {
          final original = _payload('a', 'messages');
          final p = _Prefs();
          p.values['test'] = original;
          p.failKey = failedKey;
          p.throws = throws;
          final s = HistorySnapshotStore(
            key: 'test',
            prefs: () async => p,
            decode: (raw) => decodeHistoryObject(raw, 'messages'),
            empty: <String, dynamic>{},
          );
          await s.load();
          await expectLater(
            s.save(_payload('b', 'messages')),
            throwsA(isA<HistoryStorageException>()),
          );
          expect(p.values['test'], original);
          expect(s.blocked, isTrue);
          p.failKey = null;
          await s.recover();
          expect(s.blocked, isFalse);
        },
      );
    }
  }
  for (final removal in [false, true]) {
    test(
      'optimistic prefs failed removal=$removal stays locked until durable reload',
      () async {
        final original = _payload('original', 'messages');
        final p = _OptimisticPrefs();
        p.durable.addAll({'test': original, 'test.previous': original});
        p.values.addAll(p.durable);
        final s = HistorySnapshotStore(
          key: 'test',
          prefs: () async => p,
          decode: (raw) => decodeHistoryObject(raw, 'messages'),
          empty: <String, dynamic>{},
        );
        await s.load();
        p.failKey = removal ? 'test.previous' : 'test';
        await expectLater(
          removal
              ? s.replace(_payload('new', 'messages'))
              : s.save(_payload('new', 'messages')),
          throwsA(isA<HistoryStorageException>()),
        );
        await expectLater(s.recover(), throwsA(isA<HistoryStorageException>()));
        expect(s.blocked, isTrue);
        p.failKey = null;
        p.reloadFails = false;
        expect((await s.recover())['activeId'], 'original');
        expect(s.blocked, isFalse);
        expect(p.durable['test'], original);
      },
    );
  }
  test(
    'missing main restores valid previous but isolates invalid previous',
    () async {
      final p = _Prefs()
        ..values['core.chat_sessions.v1.previous'] = _payload('a', 'messages');
      final storage = PrefsChatSessionStorage(prefs: p);
      expect((await storage.load()).activeId, 'a');
      expect(storage.recoveryState, HistoryRecoveryState.recovered);
      p.values.remove('core.chat_sessions.v1');
      p.values['core.chat_sessions.v1.previous'] = 'bad';
      await expectLater(
        PrefsChatSessionStorage(prefs: p).load(),
        throwsA(isA<HistoryStorageException>()),
      );
      expect(p.values['core.chat_sessions.v1.previous.corrupt'], isNotNull);
    },
  );
  test('replaceAll keeps files referenced by the replacement', () async {
    final p = _Prefs();
    final assets = MemoryImageAssetStore();
    final path = await assets.savePng(Uint8List.fromList([1]), 'keep');
    final repo = ChatSessionRepository(
      storage: PrefsChatSessionStorage(prefs: p),
      attachmentStore: assets,
    );
    await repo.load();
    await repo.appendMessage(
      repo.activeId,
      role: ChatRole.user,
      content: 'body',
      attachments: [ImageRef(type: ImageRefType.file, src: path)],
    );
    await repo.replaceAll(
      ChatStoreSnapshot(sessions: repo.sessions, activeId: repo.activeId),
    );
    expect(await assets.read(path), isNotNull);
    p.failKey = 'core.chat_sessions.v1';
    await expectLater(
      repo.renameSession(repo.activeId, 'new'),
      throwsA(isA<HistoryStorageException>()),
    );
    p.failKey = null;
    await repo.clearAllSessions();
    expect(await assets.read(path), isNull);
    expect(
      (await PrefsChatSessionStorage(prefs: p).load()).sessions.single.messages,
      isEmpty,
    );
    repo.dispose();
  });
  test('failed restore keeps bad original and valid previous', () async {
    final p = _Prefs()
      ..values.addAll({
        'test': 'bad',
        'test.previous': _payload('a', 'messages'),
      })
      ..failKey = 'test';
    final s = HistorySnapshotStore(
      key: 'test',
      prefs: () async => p,
      decode: (raw) => decodeHistoryObject(raw, 'messages'),
      empty: <String, dynamic>{},
    );
    await expectLater(s.load(), throwsA(isA<HistoryStorageException>()));
    expect(p.values['test'], 'bad');
    expect(p.values['test.previous'], isNotNull);
  });
}
