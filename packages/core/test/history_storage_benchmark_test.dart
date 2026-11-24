import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Opt-in, real wall-clock JIT benchmark (not a device/frame-rate test):
// flutter test --no-pub test/history_storage_benchmark_test.dart \
//   --dart-define=HISTORY_BENCHMARK=true --reporter expanded
// No network, platform history paths, credentials or timing assertions. Two
// warmups + seven measured rounds; p95 uses nearest rank, including OS IO noise.
// Windows / Flutter 3.47.4 debug-JIT baseline (1024 ASCII chars/message):
// 40x200 = 8,671,290 bytes; before -> CPU offload median/p95 milliseconds:
// first 1668/1891 -> 1713/1867; delta 1776/1838 -> 1636/1879;
// active 856/913 -> 783/845; load 553/617 -> 535/556.
// Observed event-loop delay p95: 127/153/160/134 -> 26/25/23/24 ms.
// 10x50 delta median 211 -> 219 ms (no small-history throughput claim).
// IO unchanged: first 40 revisions, delta 1, active 0 (one 4-byte write).
// All-session serialization/validation remains O(total history); this improves
// isolate availability, not device frame rate or atomic/fsync guarantees.
class _CountingFiles extends HistoryFileAccess {
  int writes = 0;
  int revisions = 0;
  int bytes = 0;
  int reads = 0;

  void reset() => writes = revisions = bytes = reads = 0;

  @override
  Future<void> write(String path, String value) async {
    writes++;
    if (path.contains('/sessions/')) revisions++;
    bytes += utf8.encode(value).length;
    await super.write(path, value);
  }

  @override
  Future<String?> read(String path) async {
    reads++;
    return super.read(path);
  }
}

ChatStoreSnapshot _fixture(int sessions, int messages) {
  final content = List.filled(1024, 'x').join();
  return ChatStoreSnapshot(
    activeId: 's0',
    sessions: [
      for (var s = 0; s < sessions; s++)
        ChatSession(
          id: 's$s',
          title: 'synthetic $s',
          createdAt: 1,
          updatedAt: 1,
          messages: [
            for (var m = 0; m < messages; m++)
              ChatMessage(
                id: 'm$m',
                role: ChatRole.assistant,
                content: content,
                createdAt: 1,
              ),
          ],
        ),
    ],
  );
}

String _encode(ChatStoreSnapshot snapshot) {
  final prepared = prepareChatPersistPayload(snapshot);
  return jsonEncode({
    'activeId': prepared.activeId,
    'sessions': prepared.sessions.map((s) => s.toJson()).toList(),
  });
}

ChatStoreSnapshot _decode(String raw) {
  final map = decodeHistoryObject(raw, 'messages');
  return prepareChatPersistPayload(
    ChatStoreSnapshot(
      sessions: (map['sessions'] as List)
          .map(
            (row) =>
                ChatSession.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList(),
      activeId: map['activeId'] as String? ?? '',
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'isolated real filesystem history benchmark',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final root = await Directory.systemTemp.createTemp('history-benchmark-');
      try {
        for (final size in [(10, 50), (40, 200)]) {
          final base = _fixture(size.$1, size.$2);
          final changed = ChatStoreSnapshot(
            sessions: [
              base.sessions.first.copyWith(title: 'changed'),
              ...base.sessions.skip(1),
            ],
            activeId: base.activeId,
          );
          final switched = ChatStoreSnapshot(
            sessions: changed.sessions,
            activeId: 's1',
          );
          final samples = <String, List<double>>{};
          final stalls = <String, List<double>>{};
          final counts = <String, List<int>>{};
          for (var round = -2; round < 7; round++) {
            final directory = Directory('${root.path}/${size.$1}-$round');
            final files = _CountingFiles();
            FileChatSessionStorage store() => FileChatSessionStorage(
              root: () async => directory,
              prefs: prefs,
              files: files,
            );
            final storage = store();
            await storage
                .load(); // Bootstrap measured separately from first data.
            Future<void> measure(
              String name,
              FutureOr<void> Function() action, {
              int? revisions,
              int? writes,
            }) async {
              files.reset();
              var maxDelay = 0;
              final clock = Stopwatch()..start();
              var last = clock.elapsedMicroseconds;
              final timer = Timer.periodic(const Duration(milliseconds: 1), (
                _,
              ) {
                final now = clock.elapsedMicroseconds;
                maxDelay = math.max(maxDelay, now - last - 1000);
                last = now;
              });
              await action();
              final elapsed = clock.elapsedMicroseconds;
              // Drain a real event turn to include blocking at the action's tail.
              await Future<void>.delayed(Duration.zero);
              maxDelay = math.max(
                maxDelay,
                clock.elapsedMicroseconds - last - 1000,
              );
              timer.cancel();
              if (revisions != null) expect(files.revisions, revisions);
              if (writes != null) expect(files.writes, writes);
              if (round >= 0) {
                (samples[name] ??= []).add(elapsed / 1000);
                (stalls[name] ??= []).add(math.max(0, maxDelay) / 1000);
                counts[name] = [
                  files.writes,
                  files.revisions,
                  files.bytes,
                  files.reads,
                ];
              }
            }

            await measure(
              'first',
              () => storage.save(base),
              revisions: size.$1,
            );
            await measure('delta', () => storage.save(changed), revisions: 1);
            await measure(
              'active',
              () => storage.save(switched),
              revisions: 0,
              writes: 1,
            );
            await measure('load', () async {
              expect((await store().load()).sessions.length, size.$1);
            }, writes: 0);
            await measure('encode_sync_reference', () {
              expect(_encode(base).length, greaterThan(0));
            }, writes: 0);
            // Same production safe IO, strict model decoder and staging; only
            // adapter prepare/toJson/compute encoding is precomputed outside
            // the timed region. This is a lower-level control, not a new path.
            final encoded = _encode(switched);
            final generic = FileHistorySnapshotStore<ChatStoreSnapshot>(
              scope: 'chat',
              legacyKey: PrefsChatSessionStorage.prefsKey,
              legacyLoad: () async =>
                  const ChatStoreSnapshot(sessions: [], activeId: ''),
              decode: _decode,
              encode: (_) async => encoded,
              empty: const ChatStoreSnapshot(sessions: [], activeId: ''),
              root: () async => directory,
              prefs: () async => prefs,
              files: files,
            );
            await generic.load();
            await measure(
              'generic_preencoded_active',
              () => generic.save(switched),
              revisions: 0,
              writes: 1,
            );
          }
          for (final entry in samples.entries) {
            final values = entry.value..sort();
            final delays = stalls[entry.key]!..sort();
            // ignore: avoid_print
            print(
              'HISTORY_BENCH ${size.$1}x${size.$2} ${entry.key} '
              'median_ms=${values[3].toStringAsFixed(3)} '
              'p95_ms=${values[6].toStringAsFixed(3)} '
              'eventloop_p95_ms=${delays[6].toStringAsFixed(3)} '
              'writes,revisions,bytes,reads=${counts[entry.key]} '
              'snapshot_bytes=${utf8.encode(_encode(base)).length}',
            );
          }
        }
      } finally {
        await root.delete(recursive: true);
      }
    },
    skip: !const bool.fromEnvironment('HISTORY_BENCHMARK'),
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
