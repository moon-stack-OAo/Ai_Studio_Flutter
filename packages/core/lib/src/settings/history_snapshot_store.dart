import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Safe, content-free status suitable for either UI.
enum HistoryRecoveryState { healthy, missing, recovered, damaged, readFailed }

class HistoryStorageException implements Exception {
  const HistoryStorageException();

  @override
  String toString() => '历史数据暂不可写入；原数据已保留，请在设置中重试恢复或明确清除数据。';
}

abstract interface class RecoverableHistoryStorage<T> {
  HistoryRecoveryState get recoveryState;
  bool get writesBlocked;
  Future<T> recover();
  Future<void> clearHistory(T empty);
  Future<void> replaceHistory(T snapshot);
}

/// One previous valid snapshot, plus immutable quarantine slots. These are local
/// recovery metadata, not an export/backup format. Never log payloads or errors.
class HistorySnapshotStore<T> {
  HistorySnapshotStore({
    required this.key,
    required this.prefs,
    required this.decode,
    required this.empty,
  });

  final String key;
  final Future<SharedPreferences> Function() prefs;
  final T Function(String) decode;
  final T empty;
  String get previousKey => '$key.previous';
  String get quarantineKey => '$key.corrupt';
  String get _clearKey => '$key.clearing';
  String get _replaceKey => '$key.replacing';
  HistoryRecoveryState state = HistoryRecoveryState.healthy;
  bool blocked = false;
  bool _needsReload = false;
  Future<void> _tail = Future<void>.value();

  Future<R> _serial<R>(Future<R> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  T _parse(Object? raw) {
    if (raw is! String || raw.isEmpty) throw const HistoryStorageException();
    return decode(raw);
  }

  bool _valid(Object? raw) {
    try {
      _parse(raw);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _put(SharedPreferences p, String k, String value) async {
    try {
      if (!await p.setString(k, value) || p.get(k) != value) {
        throw const HistoryStorageException();
      }
    } catch (_) {
      // Legacy prefs updates its cache even when the platform rejects a write.
      // Never let that optimistic cache masquerade as a durable recovery point.
      _needsReload = true;
      try {
        await p.reload();
        _needsReload = false;
      } catch (_) {}
      throw const HistoryStorageException();
    }
  }

  Future<void> _remove(SharedPreferences p, String k) async {
    try {
      if (p.containsKey(k) && (!await p.remove(k) || p.containsKey(k))) {
        throw const HistoryStorageException();
      }
    } catch (_) {
      _needsReload = true;
      try {
        await p.reload();
        _needsReload = false;
      } catch (_) {}
      throw const HistoryStorageException();
    }
  }

  Future<void> _isolate(SharedPreferences p, String slot, Object raw) async {
    final payload = jsonEncode({'value': raw});
    final existing = p.get(slot);
    // Do not overwrite an older isolated original to make room for a new one.
    if (existing != null && existing != payload) {
      throw const HistoryStorageException();
    }
    if (existing == null) await _put(p, slot, payload);
  }

  Future<T> load() => _serial(_load);
  Future<T> recover() => _serial(_load);

  Future<T> _load() async {
    blocked = true;
    state = HistoryRecoveryState.readFailed;
    try {
      final p = await prefs();
      if (_needsReload) {
        await p.reload();
        _needsReload = false;
      }
      if (p.containsKey(_clearKey)) {
        await _finishClear(p);
        blocked = false;
        state = HistoryRecoveryState.missing;
        return empty;
      }
      if (p.containsKey(_replaceKey)) {
        // An interrupted explicit deletion/replacement must never restore old data.
        await _remove(p, previousKey);
        await _remove(p, _replaceKey);
      }
      final raw = p.get(key);
      if (raw == null) {
        final previous = p.get(previousKey);
        if (previous != null) {
          if (!_valid(previous)) {
            state = HistoryRecoveryState.damaged;
            await _isolate(p, '$previousKey.corrupt', previous);
            throw const HistoryStorageException();
          }
          await _put(p, key, previous as String);
          blocked = false;
          state = HistoryRecoveryState.recovered;
          return _parse(previous);
        }
        blocked = false;
        state = HistoryRecoveryState.missing;
        return empty;
      }
      if (_valid(raw)) {
        final previous = p.get(previousKey);
        if (previous != null && !_valid(previous)) {
          state = HistoryRecoveryState.damaged;
          await _isolate(p, '$previousKey.corrupt', previous);
          await _remove(p, previousKey);
        }
        blocked = false;
        state =
            p.containsKey(quarantineKey) ||
                p.containsKey('$previousKey.corrupt')
            ? HistoryRecoveryState.recovered
            : HistoryRecoveryState.healthy;
        return _parse(raw);
      }
      state = HistoryRecoveryState.damaged;
      await _isolate(p, quarantineKey, raw);
      final previous = p.get(previousKey);
      if (!_valid(previous)) throw const HistoryStorageException();
      final snapshot = _parse(previous);
      await _put(p, key, previous as String);
      blocked = false;
      state = HistoryRecoveryState.recovered;
      return snapshot;
    } catch (_) {
      // Includes platform errors and wrong prefs value types. No payload leaks.
      throw const HistoryStorageException();
    }
  }

  Future<void> save(String payload) => _serial(() async {
    if (blocked) throw const HistoryStorageException();
    try {
      _parse(payload);
      final p = await prefs();
      if (p.containsKey(_clearKey)) throw const HistoryStorageException();
      final current = p.get(key);
      if (current != null) {
        if (!_valid(current)) {
          state = HistoryRecoveryState.damaged;
          blocked = true;
          await _isolate(p, quarantineKey, current);
          throw const HistoryStorageException();
        }
        final previous = p.get(previousKey);
        if (previous != null && !_valid(previous)) {
          await _isolate(p, '$previousKey.corrupt', previous);
        }
        // Protect the exact on-disk original before replacing the main key.
        await _put(p, previousKey, current as String);
      }
      await _put(p, key, payload);
    } catch (_) {
      blocked = true;
      if (state != HistoryRecoveryState.damaged) {
        state = HistoryRecoveryState.readFailed;
      }
      throw const HistoryStorageException();
    }
  });

  /// Explicit removal/replacement invalidates the old recovery point before
  /// committing. No assets may be deleted until this method succeeds.
  Future<void> replace(String payload) => _serial(() async {
    if (blocked) throw const HistoryStorageException();
    try {
      _parse(payload);
      final p = await prefs();
      await _put(p, _replaceKey, '1');
      await _remove(p, previousKey);
      await _put(p, key, payload);
      await _put(p, previousKey, payload);
      await _remove(p, _replaceKey);
    } catch (_) {
      blocked = true;
      state = HistoryRecoveryState.readFailed;
      throw const HistoryStorageException();
    }
  });

  Future<void> _finishClear(SharedPreferences p) async {
    for (final k in [
      previousKey,
      quarantineKey,
      '$previousKey.corrupt',
      _replaceKey,
      key,
    ]) {
      await _remove(p, k);
    }
    await _remove(p, _clearKey);
  }

  /// A durable tombstone prevents partial clears from resurrecting old history.
  Future<void> clear() => _serial(() async {
    blocked = true;
    try {
      final p = await prefs();
      await _put(p, _clearKey, '1');
      await _finishClear(p);
      blocked = false;
      state = HistoryRecoveryState.missing;
    } catch (_) {
      state = HistoryRecoveryState.readFailed;
      throw const HistoryStorageException();
    }
  });
}

/// Validate before tolerant model decoders can silently discard malformed rows.
/// Optional fields stay optional for older app versions; present fields must
/// retain their shape. Existing history caps/sanitizers remain unchanged.
Map<String, dynamic> decodeHistoryObject(String raw, String children) {
  final root = jsonDecode(raw);
  if (root is! Map<String, dynamic> ||
      root['sessions'] is! List ||
      (root['activeId'] != null && root['activeId'] is! String)) {
    throw const HistoryStorageException();
  }
  void validateMap(Map value) {
    for (final entry in value.entries) {
      final v = entry.value;
      if (v == null) continue;
      const numeric = [
        'createdAt',
        'updatedAt',
        'latencyMs',
        'temperature',
        'n',
        'progress',
        'duration',
      ];
      const booleans = [
        'streaming',
        'stopped',
        'error',
        'needsResume',
        'needsMaterialize',
      ];
      const strings = [
        'id',
        'title',
        'content',
        'role',
        'prompt',
        'finalPrompt',
        'model',
        'providerId',
        'providerName',
        'status',
        'mode',
        'src',
        'type',
        'errorMessage',
        'systemPrompt',
        'jobId',
        'videoUrl',
        'remoteVideoUrl',
        'localPath',
        'posterUrl',
        'posterLocalPath',
        'thumbnailUrl',
        'coverUrl',
        'refPreview',
        'revisedPrompt',
        'size',
        'aspectRatio',
        'resolution',
        'quality',
        'name',
        'arguments',
        'toolCallId',
        'tool_call_id',
        'toolResultStatus',
        'rules',
      ];
      if ((numeric.contains(entry.key) && v is! num) ||
          (booleans.contains(entry.key) && v is! bool) ||
          (strings.contains(entry.key) && v is! String) ||
          (['overrides', 'function'].contains(entry.key) && v is! Map)) {
        throw const HistoryStorageException();
      }
      if (const [
        'messages',
        'items',
        'attachments',
        'images',
        'referenceImages',
        'toolCalls',
        'tool_calls',
        'appliedSkills',
      ].contains(entry.key)) {
        if (v is! List || v.any((e) => e is! Map)) {
          throw const HistoryStorageException();
        }
      }
      if (v is Map && ['overrides', 'function'].contains(entry.key)) {
        validateMap(v);
      }
      if (v is List &&
          [
            'messages',
            'items',
            'attachments',
            'images',
            'referenceImages',
            'toolCalls',
            'tool_calls',
            'appliedSkills',
          ].contains(entry.key)) {
        for (final e in v) {
          if (e is Map) validateMap(e);
        }
      }
    }
  }

  final ids = <String>{};
  for (final session in root['sessions'] as List) {
    if (session is! Map ||
        session['id'] is! String ||
        (session['id'] as String).isEmpty ||
        !ids.add(session['id'] as String) ||
        (session.containsKey(children) && session[children] is! List)) {
      throw const HistoryStorageException();
    }
    validateMap(session);
    final rowIds = <String>{};
    for (final row in (session[children] as List? ?? const [])) {
      if (row is! Map ||
          row['id'] is! String ||
          (row['id'] as String).isEmpty ||
          !rowIds.add(row['id'] as String)) {
        throw const HistoryStorageException();
      }
    }
  }
  return root;
}
