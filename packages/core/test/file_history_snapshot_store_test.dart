import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Files extends HistoryFileAccess {
  final values = <String, String>{};
  final writes = <String>[];
  String? failWrite;
  String? failRead;
  String? tearWrite;
  String? mismatchRead;
  String? failRemove;
  String? ignoreRemove;
  @override
  Future<String?> read(String path) async {
    if (failRead != null && path.contains(failRead!)) {
      throw const FileSystemException('private IO failure');
    }
    if (mismatchRead != null &&
        path.contains(mismatchRead!) &&
        writes.contains(path)) {
      return 'readback mismatch';
    }
    return values[path];
  }

  @override
  Future<void> write(String path, String value) async {
    writes.add(path);
    if (tearWrite != null && path.endsWith(tearWrite!)) {
      values[path] = '{torn';
      throw const FileSystemException('interrupted');
    }
    if (failWrite != null && path.contains(failWrite!)) {
      throw const FileSystemException('interrupted');
    }
    values[path] = value;
  }

  @override
  Future<void> remove(String path) async {
    if (failRemove != null && path.endsWith(failRemove!)) {
      throw const FileSystemException('remove interrupted');
    }
    if (ignoreRemove != null && path.endsWith(ignoreRemove!)) return;
    values.remove(path);
  }

  @override
  Future<List<String>> files(String path) async => values.keys
      .where(
        (key) =>
            key.startsWith('$path/') &&
            !key.substring(path.length + 1).contains('/'),
      )
      .toList();
}

class _Prefs implements SharedPreferences {
  final values = <String, Object>{};
  String? failRemove;
  @override
  Object? get(String key) => values[key];
  @override
  bool containsKey(String key) => values.containsKey(key);
  @override
  Future<bool> setString(String key, String value) async {
    values[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    if (key == failRemove) return false;
    values.remove(key);
    return true;
  }

  @override
  Future<void> reload() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ChatStoreSnapshot _chat(
  String title, {
  String active = 'a',
  bool second = true,
}) => ChatStoreSnapshot(
  sessions: [
    ChatSession(id: 'a', title: title, createdAt: 1, updatedAt: 1),
    if (second)
      const ChatSession(
        id: 'b',
        title: 'unchanged',
        createdAt: 1,
        updatedAt: 1,
      ),
  ],
  activeId: active,
);

String _validateJson(String raw) {
  jsonDecode(raw);
  return raw;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Files files;
  late _Prefs prefs;
  FileChatSessionStorage store() => FileChatSessionStorage(
    root: () async => Directory('test-history'),
    prefs: prefs,
    files: files,
  );
  setUp(() {
    files = _Files();
    prefs = _Prefs();
  });

  test(
    'migration validates commit before cleanup, quarantine stays inert',
    () async {
      prefs.values[PrefsChatSessionStorage.prefsKey] = jsonEncode({
        'sessions': [
          const ChatSession(
            id: '../external',
            title: 'old',
            createdAt: 1,
            updatedAt: 1,
          ).toJson(),
        ],
        'activeId': '../external',
      });
      prefs.values['${PrefsChatSessionStorage.prefsKey}.corrupt'] =
          'exact original';
      final s = store();
      expect((await s.load()).sessions.single.title, 'old');
      expect(prefs.containsKey(PrefsChatSessionStorage.prefsKey), isFalse);
      expect(
        prefs.values['${PrefsChatSessionStorage.prefsKey}.corrupt'],
        'exact original',
      );
      expect(files.values.keys.any((p) => p.contains('../external')), isFalse);
      prefs.values[PrefsChatSessionStorage.prefsKey] = jsonEncode({
        'sessions': [],
        'activeId': '',
      });
      expect((await store().load()).sessions.single.title, 'old');
    },
  );

  test(
    'active-only writes no session or manifest; changed session only once',
    () async {
      final s = store();
      await s.load();
      await s.save(_chat('one'));
      files.writes.clear();
      await s.save(_chat('one', active: 'b'));
      expect(files.writes.length, 1);
      expect(files.writes.single.endsWith('/active.json'), isTrue);
      files.writes.clear();
      await s.save(_chat('two', active: 'b'));
      expect(files.writes.where((p) => p.contains('/sessions/')).length, 1);
      expect((await store().load()).activeId, 'b');
    },
  );

  test('large invalid worker payload is private and cannot publish', () async {
    final generic = FileHistorySnapshotStore<String>(
      scope: 'worker-invalid',
      legacyKey: 'worker-invalid',
      legacyLoad: () async => '{"sessions":[],"activeId":""}',
      decode: _validateJson,
      encode: (s) async => s,
      empty: '{"sessions":[],"activeId":""}',
      root: () async => Directory('test-worker-invalid'),
      prefs: () async => prefs,
      files: files,
    );
    await generic.load();
    files.writes.clear();
    final secret = 'private${List.filled(80 * 1024, 'x').join()}';
    try {
      await generic.save('{$secret');
      fail('invalid payload accepted');
    } catch (error) {
      expect(error, isA<HistoryStorageException>());
      expect(error.toString(), isNot(contains('private')));
    }
    expect(files.writes, isEmpty);
    expect(generic.writesBlocked, isTrue);
  });

  test(
    'large worker roundtrip preserves content and revision counts',
    () async {
      final content = List.filled(80 * 1024, 'x').join();
      final large = ChatStoreSnapshot(
        sessions: [
          ChatSession(
            id: 'a',
            title: 'large',
            createdAt: 1,
            updatedAt: 1,
            messages: [
              ChatMessage(
                id: 'm',
                role: ChatRole.assistant,
                content: content,
                createdAt: 1,
              ),
            ],
          ),
          _chat('small').sessions.last,
        ],
        activeId: 'a',
      );
      final s = store();
      await s.load();
      await s.save(large);
      files.writes.clear();
      await s.save(ChatStoreSnapshot(sessions: large.sessions, activeId: 'b'));
      expect(files.writes.single.endsWith('/active.json'), isTrue);
      final loaded = await store().load();
      expect(loaded.activeId, 'b');
      expect(loaded.sessions.first.messages.single.content, content);
      final session = files.values.keys.firstWhere(
        (p) => p.contains('/sessions/') && files.values[p]!.contains(content),
      );
      files.values[session] = '{private${List.filled(80 * 1024, 'x').join()}';
      final recovered = store();
      expect((await recovered.load()).sessions, isEmpty);
      expect(recovered.recoveryState, HistoryRecoveryState.recovered);
      expect(files.values.values.any((s) => s.contains('private')), isTrue);
    },
  );

  test(
    'ordinary GC keeps current and previous, replace deletes old revisions',
    () async {
      final s = store();
      await s.load();
      for (final title in ['one', 'two', 'three', 'four']) {
        await s.save(_chat(title));
      }
      expect(
        files.values.keys.where((p) => p.contains('/sessions/')).length,
        3,
      );
      await s.replaceHistory(_chat('only', second: false));
      expect(
        files.values.keys.where((p) => p.contains('/sessions/')).length,
        1,
      );
      expect(files.values.keys.where((p) => p.endsWith('/previous')), isEmpty);
      final current = files.values.keys.singleWhere(
        (p) => p.endsWith('/commit'),
      );
      files.values[current] = 'broken';
      await expectLater(
        store().load(),
        throwsA(isA<HistoryStorageException>()),
      );
    },
  );

  test('session corruption is isolated before previous recovery', () async {
    final s = store();
    await s.load();
    await s.save(_chat('one'));
    await s.save(_chat('two'));
    final session = files.writes.lastWhere((p) => p.contains('/sessions/'));
    files.values[session] = '{private';
    expect((await store().load()).sessions.first.title, 'one');
    expect(
      files.values.values.any((raw) => raw.contains('"text":"{private"')),
      isTrue,
    );
    expect(files.values.keys.any((p) => p.contains('/quarantine/')), isTrue);
  });

  test(
    'IO read failure locks without modifying commit or restoring previous',
    () async {
      final s = store();
      await s.load();
      await s.save(_chat('one'));
      await s.save(_chat('two'));
      final before = Map<String, String>.from(files.values);
      files.failRead = '/sessions/';
      final next = store();
      await expectLater(next.load(), throwsA(isA<HistoryStorageException>()));
      expect(next.writesBlocked, isTrue);
      expect(files.values, before);
      files.failRead = null;
      expect((await next.recover()).sessions.first.title, 'two');
    },
  );

  for (final damage in ['missing', 'hash', 'shape', 'digest']) {
    test('valid current retires damaged previous $damage', () async {
      final s = store();
      await s.load();
      await s.save(_chat('old'));
      final hasSecond = damage != 'missing';
      await s.save(
        _chat('current', active: hasSecond ? 'b' : 'a', second: hasSecond),
      );
      final previous = files.values.keys.singleWhere(
        (p) => p.endsWith('/previous'),
      );
      final base = previous.substring(0, previous.length - 'previous'.length);
      var manifest = '${base}manifests/${files.values[previous]}.json';
      if (damage == 'missing') {
        files.values.remove(manifest);
      } else if (damage == 'hash') {
        files.values[manifest] = '{private broken manifest';
      } else if (damage == 'shape') {
        const raw = '{"schema":1,"refs":[{}]}';
        final digest = sha256.convert(utf8.encode(raw)).toString();
        manifest = '${base}manifests/$digest.json';
        files.values[manifest] = raw;
        files.values[previous] = digest;
      } else {
        files.values[previous] = '../invalid digest';
      }
      final pointerRaw = files.values[previous]!;
      final manifestRaw = files.values[manifest];
      final commit = files.values['${base}commit'];
      final active = files.values['${base}active.json'];
      final next = store();
      final loaded = await next.load();
      expect(loaded.sessions.first.title, 'current');
      expect(loaded.sessions.length, hasSecond ? 2 : 1);
      expect(loaded.activeId, hasSecond ? 'b' : 'a');
      expect(next.writesBlocked, isFalse);
      expect(next.recoveryState, HistoryRecoveryState.recovered);
      expect(files.values[previous], isNull);
      expect(files.values['${base}commit'], commit);
      expect(files.values['${base}active.json'], active);
      final envelopes = files.values.entries
          .where((e) => e.key.contains('/quarantine/'))
          .map((e) => jsonDecode(e.value) as Map);
      expect(envelopes.any((e) => e['text'] == pointerRaw), isTrue);
      if (['hash', 'shape'].contains(damage)) {
        expect(envelopes.any((e) => e['text'] == manifestRaw), isTrue);
      }
      expect((await next.recover()).sessions.first.title, 'current');
      expect((await store().load()).sessions.first.title, 'current');
      await next.save(_chat('continued', second: false));
      expect((await store().load()).sessions.single.title, 'continued');
    });
  }

  test(
    'both invalid authorities stay locked without legacy fallback',
    () async {
      final s = store();
      await s.load();
      await s.save(_chat('current'));
      for (final path
          in files.values.keys
              .where((p) => p.endsWith('/commit') || p.endsWith('/previous'))
              .toList()) {
        files.values[path] = 'broken';
      }
      prefs.values[PrefsChatSessionStorage.prefsKey] = '{legacy must not run';
      final next = store();
      await expectLater(next.load(), throwsA(isA<HistoryStorageException>()));
      await expectLater(
        next.recover(),
        throwsA(isA<HistoryStorageException>()),
      );
      expect(next.writesBlocked, isTrue);
      expect(files.values.values.where((v) => v == 'broken').length, 2);
    },
  );

  for (final target in ['pointer', 'manifest']) {
    test(
      'previous $target temporary IO keeps authority and is retryable',
      () async {
        final s = store();
        await s.load();
        await s.save(_chat('old'));
        await s.save(_chat('current', active: 'b'));
        final previous = files.values.keys.singleWhere(
          (p) => p.endsWith('/previous'),
        );
        final before = Map<String, String>.from(files.values);
        files.failRead = target == 'pointer'
            ? previous
            : '/manifests/${files.values[previous]}.json';
        final next = store();
        await expectLater(next.load(), throwsA(isA<HistoryStorageException>()));
        expect(next.writesBlocked, isTrue);
        expect(files.values, before);
        files.failRead = null;
        expect((await next.recover()).sessions.first.title, 'current');
        expect((await store().load()).activeId, 'b');
      },
    );
  }

  for (final failure in [
    'isolate',
    'readback',
    'conflict',
    'manifest-conflict',
    'remove',
    'silent-remove',
    'gc',
  ]) {
    test(
      'previous retirement $failure failure retains data and stays locked',
      () async {
        final s = store();
        await s.load();
        await s.save(_chat('old'));
        await s.save(_chat('current'));
        final previous = files.values.keys.singleWhere(
          (p) => p.endsWith('/previous'),
        );
        final base = previous.substring(0, previous.length - 'previous'.length);
        var isolated = 'previous';
        if (failure == 'manifest-conflict') {
          isolated = 'manifests/${files.values[previous]}.json';
          files.values['$base$isolated'] = '{broken manifest';
        } else {
          files.values[previous] = 'bad pointer';
        }
        final slot =
            '${base}quarantine/${sha256.convert(utf8.encode(isolated))}.json';
        if (failure.endsWith('conflict')) files.values[slot] = 'older original';
        final before = Map<String, String>.from(files.values);
        if (failure == 'isolate') files.failWrite = '/quarantine/';
        if (failure == 'readback') files.mismatchRead = '/quarantine/';
        if (failure == 'remove') files.failRemove = '/previous';
        if (failure == 'silent-remove') files.ignoreRemove = '/previous';
        if (failure == 'gc') {
          final base = previous.substring(
            0,
            previous.length - 'previous'.length,
          );
          final current = files.values['${base}commit'];
          final obsolete = files.values.keys.firstWhere(
            (p) => p.contains('/manifests/') && !p.endsWith('/$current.json'),
          );
          files.failRemove = obsolete;
        }
        final next = store();
        await expectLater(next.load(), throwsA(isA<HistoryStorageException>()));
        expect(next.writesBlocked, isTrue);
        for (final entry in before.entries) {
          if (failure == 'gc' && entry.key == previous) continue;
          expect(files.values[entry.key], entry.value);
        }
        if (!failure.endsWith('conflict')) {
          files.failWrite = null;
          files.mismatchRead = null;
          files.failRemove = null;
          files.ignoreRemove = null;
          expect((await next.recover()).sessions.first.title, 'current');
          expect((await store().load()).sessions.first.title, 'current');
        } else {
          expect(files.values[slot], 'older original');
        }
      },
    );
  }

  test(
    'active corruption recovers selection without discarding sessions',
    () async {
      final s = store();
      await s.load();
      await s.save(_chat('one', active: 'b'));
      final active = files.values.keys.singleWhere(
        (p) => p.endsWith('/active.json'),
      );
      files.values[active] = '[]';
      final next = store();
      final snapshot = await next.load();
      expect(snapshot.sessions.length, 2);
      expect(snapshot.activeId, 'a');
      expect(next.recoveryState, HistoryRecoveryState.recovered);
    },
  );

  for (final failure in [
    '/sessions/',
    '/manifests/',
    '/pending.json',
    '/commit',
    '/active.json',
  ]) {
    test(
      'write failure $failure never reverts acknowledged deletion on restart',
      () async {
        final s = store();
        await s.load();
        await s.save(_chat('one'));
        files.failWrite = failure;
        await expectLater(
          s.replaceHistory(_chat('two', second: false)),
          throwsA(isA<HistoryStorageException>()),
        );
        files.failWrite = null;
        final next = store();
        final result = await next.load();
        // Before the journal, no deletion was committed; after it, only target may recover.
        if (['/commit', '/active.json'].contains(failure)) {
          expect(result.sessions.length, 1);
          expect(result.sessions.first.title, 'two');
        } else {
          expect(result.sessions.length, 2);
        }
      },
    );
  }

  test(
    'torn deletion journal blocks every restart/recovery until explicit clear',
    () async {
      final s = store();
      await s.load();
      await s.save(_chat('one'));
      files.tearWrite = '/pending.json';
      await expectLater(
        s.replaceHistory(_chat('two', second: false)),
        throwsA(isA<HistoryStorageException>()),
      );
      files.tearWrite = null;
      final next = store();
      await expectLater(next.load(), throwsA(isA<HistoryStorageException>()));
      await expectLater(
        next.recover(),
        throwsA(isA<HistoryStorageException>()),
      );
      await next.clearHistory(
        const ChatStoreSnapshot(sessions: [], activeId: ''),
      );
      expect((await store().load()).sessions, isEmpty);
    },
  );

  test(
    'legacy cleanup failure locks new authority and retry does not fallback',
    () async {
      final key = PrefsChatSessionStorage.prefsKey;
      prefs.values[key] = jsonEncode({
        'sessions': [
          const ChatSession(
            id: 'old',
            title: 'old',
            createdAt: 1,
            updatedAt: 1,
          ).toJson(),
        ],
        'activeId': 'old',
      });
      prefs.failRemove = key;
      final s = store();
      await expectLater(s.load(), throwsA(isA<HistoryStorageException>()));
      expect(s.writesBlocked, isTrue);
      prefs.values[key] = '{stale';
      prefs.failRemove = null;
      expect((await store().load()).sessions.single.id, 'old');
    },
  );

  test(
    'commit readback failure resumes target, cleanup remove failure resumes deletion',
    () async {
      final s = store();
      await s.load();
      await s.save(_chat('one'));
      files.mismatchRead = '/commit';
      files.writes.clear();
      await expectLater(
        s.replaceHistory(_chat('two', second: false)),
        throwsA(isA<HistoryStorageException>()),
      );
      files.mismatchRead = null;
      expect((await store().load()).sessions.single.title, 'two');
      final next = store();
      await next.load();
      files.failRemove = '/pending.json';
      await expectLater(
        next.replaceHistory(_chat('three', second: false)),
        throwsA(isA<HistoryStorageException>()),
      );
      files.failRemove = null;
      expect((await store().load()).sessions.single.title, 'three');
    },
  );

  test('stage readback failure keeps old commit and locks writes', () async {
    final s = store();
    await s.load();
    await s.save(_chat('one'));
    files.writes.clear();
    files.mismatchRead = '/sessions/';
    await expectLater(
      s.save(_chat('two')),
      throwsA(isA<HistoryStorageException>()),
    );
    expect(s.writesBlocked, isTrue);
    files.mismatchRead = null;
    expect((await store().load()).sessions.first.title, 'one');
  });

  test('completed migration no longer consults prefs on restart', () async {
    final s = store();
    await s.load();
    await s.save(_chat('one'));
    final next = FileHistorySnapshotStore<ChatStoreSnapshot>(
      scope: 'chat',
      legacyKey: PrefsChatSessionStorage.prefsKey,
      legacyLoad: () async => throw StateError('legacy must not run'),
      decode: (raw) {
        final value = jsonDecode(raw) as Map;
        return ChatStoreSnapshot(
          sessions: (value['sessions'] as List)
              .map(
                (r) =>
                    ChatSession.fromJson(Map<String, dynamic>.from(r as Map)),
              )
              .toList(),
          activeId: value['activeId'] as String,
        );
      },
      encode: (_) async => throw StateError('encode must not run'),
      empty: const ChatStoreSnapshot(sessions: [], activeId: ''),
      root: () async => Directory('test-history'),
      files: files,
      prefs: () async => throw StateError('prefs offline'),
    );
    expect((await next.load()).sessions.first.title, 'one');
  });

  test(
    'legacy quarantine conflict blocks migration without destroying originals',
    () async {
      final key = PrefsChatSessionStorage.prefsKey;
      prefs.values[key] = '{damaged';
      prefs.values['$key.corrupt'] = 'older original';
      final s = store();
      await expectLater(s.load(), throwsA(isA<HistoryStorageException>()));
      expect(s.writesBlocked, isTrue);
      expect(prefs.values[key], '{damaged');
      expect(prefs.values['$key.corrupt'], 'older original');
      expect(files.values.keys.where((p) => p.endsWith('/commit')), isEmpty);
    },
  );

  for (final marker in ['previous', 'clearing', 'replacing']) {
    test(
      'legacy $marker migration preserves recovery and deletion semantics',
      () async {
        final key = PrefsChatSessionStorage.prefsKey;
        final old = jsonEncode({
          'sessions': _chat('old').sessions.map((s) => s.toJson()).toList(),
          'activeId': 'a',
        });
        prefs.values['$key.previous'] = old;
        if (marker != 'previous') prefs.values['$key.$marker'] = '1';
        final s = store();
        final result = await s.load();
        expect(result.sessions.length, marker == 'previous' ? 2 : 0);
        prefs.values[key] = old;
        expect(
          (await store().load()).sessions.length,
          marker == 'previous' ? 2 : 0,
        );
      },
    );
  }

  for (final failure in ['corrupt', 'io']) {
    test(
      'pending target $failure locks instead of recovering old commit',
      () async {
        final s = store();
        await s.load();
        await s.save(_chat('one'));
        files.failWrite = '/commit';
        await expectLater(
          s.save(_chat('two')),
          throwsA(isA<HistoryStorageException>()),
        );
        files.failWrite = null;
        final target = files.writes.lastWhere((p) => p.contains('/sessions/'));
        final original = files.values[target]!;
        if (failure == 'corrupt') {
          files.values[target] = '{broken';
        } else {
          files.failRead = target;
        }
        final next = store();
        await expectLater(next.load(), throwsA(isA<HistoryStorageException>()));
        expect(next.writesBlocked, isTrue);
        files.failRead = null;
        files.values[target] = original;
        expect((await store().load()).sessions.first.title, 'two');
      },
    );
  }

  for (final kind in [
    'sessions',
    'manifests',
    'active.json',
    'previous-manifest',
    'previous-pointer',
  ]) {
    test('invalid UTF8 $kind preserves exact bytes and recovers', () async {
      final root = await Directory.systemTemp.createTemp('history-bytes-');
      try {
        final s = FileChatSessionStorage(root: () async => root, prefs: prefs);
        await s.load();
        await s.save(_chat('one'));
        await s.save(_chat('two'));
        final all = await root
            .list(recursive: true)
            .where((e) => e is File)
            .toList();
        File target;
        if (kind == 'active.json') {
          target = File(
            all.singleWhere((e) => e.path.endsWith('active.json')).path,
          );
        } else {
          final pointer = kind.startsWith('previous-') ? 'previous' : 'commit';
          final commit = File(
            all
                .singleWhere(
                  (e) => e.path.endsWith('${Platform.pathSeparator}$pointer'),
                )
                .path,
          );
          final digest = await commit.readAsString();
          final manifest = File('${commit.parent.path}/manifests/$digest.json');
          if (kind == 'previous-pointer') {
            target = commit;
          } else if (kind == 'manifests' || kind == 'previous-manifest') {
            target = manifest;
          } else {
            final revision =
                ((jsonDecode(await manifest.readAsString()) as Map)['refs']
                        as List)
                    .first['revision'];
            target = File(
              all.singleWhere((e) => e.path.endsWith('-$revision.json')).path,
            );
          }
        }
        const broken = [0xff, 0xfe, 0x80];
        await target.writeAsBytes(broken);
        final next = FileChatSessionStorage(
          root: () async => root,
          prefs: prefs,
        );
        expect(
          (await next.load()).sessions.first.title,
          kind == 'active.json' || kind.startsWith('previous-') ? 'two' : 'one',
        );
        final quarantines = await root
            .list(recursive: true)
            .where((e) => e is File && e.parent.path.endsWith('quarantine'))
            .toList();
        final envelopes = await Future.wait(
          quarantines.map((e) => File(e.path).readAsString()),
        );
        expect(
          envelopes.any((raw) {
            final value = jsonDecode(raw) as Map;
            return value['encoding'] == 'base64' &&
                base64Decode(value['bytes'] as String).join(',') ==
                    broken.join(',');
          }),
          isTrue,
        );
      } finally {
        await root.delete(recursive: true);
      }
    });
  }

  test(
    'trusted support alias resolves before history IO and recovery',
    () async {
      final temp = await Directory.systemTemp.createTemp('history-support-');
      try {
        final support = await Directory('${temp.path}/support').create();
        final alias = Link('${temp.path}/alias');
        await alias.create(support.path);
        final root = await historyRootFromApplicationSupport(
          Directory(alias.path),
        );
        expect(root.path, '${await support.resolveSymbolicLinks()}/history_v2');
        final s = FileChatSessionStorage(root: () async => root, prefs: prefs);
        await s.load();
        await s.save(_chat('retained'));
        final restart = FileChatSessionStorage(
          root: () async => root,
          prefs: prefs,
        );
        expect((await restart.load()).sessions.first.title, 'retained');
        expect((await restart.recover()).sessions.first.title, 'retained');
        expect(restart.writesBlocked, isFalse);
      } finally {
        await temp.delete(recursive: true);
      }
    },
    skip: Platform.isWindows
        ? 'POSIX system alias regression (iOS/macOS/Linux)'
        : false,
  );

  test('trusted support produces canonical managed history root', () async {
    final temp = await Directory.systemTemp.createTemp('history-canonical-');
    try {
      final root = await historyRootFromApplicationSupport(temp);
      expect(root.path, '${await temp.resolveSymbolicLinks()}/history_v2');
      final s = FileChatSessionStorage(root: () async => root, prefs: prefs);
      await s.load();
      await s.save(_chat('retained'));
      expect((await s.recover()).sessions.first.title, 'retained');
    } finally {
      await temp.delete(recursive: true);
    }
  });

  for (final location in ['history_v2', 'scope', 'sessions', 'commit']) {
    test(
      'managed $location link remains blocked after support resolution',
      () async {
        final temp = await Directory.systemTemp.createTemp('history-link-');
        try {
          final support = await Directory('${temp.path}/support').create();
          final outside = await Directory('${temp.path}/outside').create();
          final marker = File('${outside.path}/marker');
          await marker.writeAsString('unchanged');
          final root = await historyRootFromApplicationSupport(support);
          final s = FileChatSessionStorage(
            root: () async => root,
            prefs: prefs,
          );
          await s.load();
          await s.save(_chat('retained'));
          final scope = (await root.list().toList()).single as Directory;
          final target = switch (location) {
            'history_v2' => root.path,
            'scope' => scope.path,
            'sessions' => '${scope.path}/sessions',
            _ => '${scope.path}/commit',
          };
          if (location == 'commit') {
            await File(target).delete();
            await Link(target).create(marker.path);
          } else {
            await Directory(target).delete(recursive: true);
            await Link(target).create(outside.path);
          }
          final restart = FileChatSessionStorage(
            root: () async => root,
            prefs: prefs,
          );
          await expectLater(
            restart.load(),
            throwsA(isA<HistoryStorageException>()),
          );
          expect(restart.writesBlocked, isTrue);
          expect(await marker.readAsString(), 'unchanged');
          expect((await outside.list().toList()).length, 1);
        } finally {
          await temp.delete(recursive: true);
        }
      },
      skip: Platform.isWindows ? 'POSIX symlink safety regression' : false,
    );
  }

  test(
    'real file store and Windows basenames retain current revisions',
    () async {
      final root = await Directory.systemTemp.createTemp('history-file-test-');
      try {
        final s = FileChatSessionStorage(root: () async => root, prefs: prefs);
        await s.load();
        await s.save(_chat('real'));
        await s.save(_chat('next'));
        final restart = FileChatSessionStorage(
          root: () async => root,
          prefs: prefs,
        );
        expect((await restart.load()).sessions.first.title, 'next');
        await restart.clearHistory(
          const ChatStoreSnapshot(sessions: [], activeId: ''),
        );
        expect((await restart.load()).sessions, isEmpty);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}
