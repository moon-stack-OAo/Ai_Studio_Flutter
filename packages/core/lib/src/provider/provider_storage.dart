import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'provider_config.dart';
import 'provider_presets.dart';
import 'secret_store.dart';

/// 提供商持久化快照（元数据 + 选中项；密钥另存）。
class ProviderStoreSnapshot {
  const ProviderStoreSnapshot({
    required this.providers,
    required this.activeProviderId,
  });

  final List<ProviderConfig> providers;
  final String activeProviderId;
}

/// 提供商存储抽象（便于单元测试用内存实现）。
abstract class ProviderStorage {
  Future<ProviderStoreSnapshot> load();

  Future<void> save(ProviderStoreSnapshot snapshot);
}

/// 生产存储：
/// - 元数据 → `shared_preferences`：`core.providers.v1`（**不含** apiKey）
/// - 密钥 → OS 凭据库（`flutter_secure_storage`）：`core.provider.keys.v1`
///
/// 首次启动会把旧版明文 prefs 密钥（同名键）一次性迁入安全存储，成功后再清除明文。
/// 迁移失败**不**静默清空明文，并打错误日志（脱敏，不含 Key 内容）。
class SecureProviderStorage implements ProviderStorage {
  SecureProviderStorage({
    SharedPreferences? prefs,
    SecretStore? secretStore,
  })  : _prefsOverride = prefs,
        _secrets = GuardedSecretStore(secretStore ?? FlutterSecureSecretStore());

  /// 元数据 prefs 键。
  static const prefsMetaKey = 'core.providers.v1';

  /// 密钥映射键（安全存储与旧版明文 prefs 同名，便于迁移识别）。
  static const keysStorageKey = 'core.provider.keys.v1';

  final SharedPreferences? _prefsOverride;
  final SecretStore _secrets;
  SharedPreferences? _prefs;

  // A timeout does not cancel a platform write. Reject new saves until it settles.
  Future<void>? _secureWriteInFlight;
  bool _saving = false;
  bool get hasPendingWrites => _saving || _secureWriteInFlight != null || (_secrets as GuardedSecretStore).isPending;
  void _checkPending() {
    if (hasPendingWrites) throw StateError('安全存储仍在处理中，请稍后重试');
  }

  /// 最近一次密钥迁移结果（供诊断；不含密钥明文）。
  String? lastMigrationNote;

  Future<SharedPreferences> _ensurePrefs() async {
    return _prefs ??= _prefsOverride ?? await SharedPreferences.getInstance();
  }

  Map<String, String> _decodeKeyMap(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, String>{};
      for (final e in decoded.entries) {
        final id = e.key.toString();
        final v = e.value;
        if (id.isEmpty || v is! String) continue;
        out[id] = v;
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, String>> _readSecureKeys() async {
    final raw = await _secrets.read(keysStorageKey);
    return _decodeKeyMap(raw);
  }

  Future<void> _writeSecureKeys(Map<String, String> keys) async {
    if (keys.isEmpty) {
      await _secrets.delete(keysStorageKey);
      return;
    }
    await _secrets.write(keysStorageKey, jsonEncode(keys));
  }

  /// 旧版明文 → 安全存储；成功才删明文。失败保留明文并记日志。
  Future<Map<String, String>> _migratePlaintextKeysIfNeeded(
    SharedPreferences prefs,
  ) async {
    final legacyRaw = prefs.getString(keysStorageKey);
    if (legacyRaw == null || legacyRaw.isEmpty) {
      lastMigrationNote = null;
      return _readSecureKeys();
    }

    final legacy = _decodeKeyMap(legacyRaw);
    if (legacy.isEmpty) {
      // 损坏 / 空映射：仍尝试清除明文壳，避免残留。
      try {
        await prefs.remove(keysStorageKey);
        lastMigrationNote = 'cleared empty legacy provider keys prefs';
      } catch (_) {
        lastMigrationNote = 'failed to clear empty legacy keys';
        debugPrint('[SecureProviderStorage] $lastMigrationNote');
      }
      return _readSecureKeys();
    }

    try {
      final secure = await _readSecureKeys();
      // 安全侧已有的 id 优先；明文仅补缺，避免覆盖更新后的值。
      final merged = <String, String>{...legacy, ...secure};
      await _writeSecureKeys(merged);

      // 写后回读校验，失败则保留明文。
      final verified = await _readSecureKeys();
      for (final e in merged.entries) {
        if (verified[e.key] != e.value) {
          throw StateError(
            'secure key verify mismatch for provider id=${e.key}',
          );
        }
      }

      await prefs.remove(keysStorageKey);
      lastMigrationNote =
          'migrated ${legacy.length} provider key(s) from prefs to secure storage';
      debugPrint('[SecureProviderStorage] $lastMigrationNote');
      return verified;
    } catch (_) {
      lastMigrationNote =
          'migration failed; plaintext prefs keys retained';
      debugPrint('[SecureProviderStorage] $lastMigrationNote');
      // 失败安全：用明文继续，不删 prefs。
      Map<String, String> secure = {};
      try {
        secure = await _readSecureKeys();
      } catch (_) {
        secure = {};
      }
      return {...legacy, ...secure};
    }
  }

  @override
  Future<ProviderStoreSnapshot> load() async {
    _checkPending();
    final prefs = await _ensurePrefs();
    final keyMap = await _migratePlaintextKeysIfNeeded(prefs);

    final raw = prefs.getString(prefsMetaKey);
    if (raw == null || raw.isEmpty) {
      final presets = builtinProviderPresets();
      return ProviderStoreSnapshot(
        providers: presets,
        activeProviderId: presets.first.id,
      );
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      final presets = builtinProviderPresets();
      return ProviderStoreSnapshot(
        providers: presets,
        activeProviderId: presets.first.id,
      );
    }

    final listRaw = decoded['providers'];
    final items = <ProviderConfig>[];
    if (listRaw is List) {
      for (final entry in listRaw) {
        if (entry is! Map) continue;
        final map = Map<String, dynamic>.from(entry);
        final id = (map['id'] as String?)?.trim() ?? '';
        if (id.isEmpty) continue;
        items.add(
          ProviderConfig.fromJson(map, apiKey: keyMap[id] ?? ''),
        );
      }
    }

    if (items.isEmpty) {
      final presets = builtinProviderPresets();
      return ProviderStoreSnapshot(
        providers: presets,
        activeProviderId: presets.first.id,
      );
    }

    final active = (decoded['activeProviderId'] as String?)?.trim() ?? '';
    final activeId =
        items.any((p) => p.id == active) ? active : items.first.id;
    return ProviderStoreSnapshot(providers: items, activeProviderId: activeId);
  }

  @override
  Future<void> save(ProviderStoreSnapshot snapshot) async {
    _checkPending();
    _saving = true;
    try {
    final prefs = await _ensurePrefs();
    final providers = snapshot.providers;
    final activeId = providers.any((p) => p.id == snapshot.activeProviderId)
        ? snapshot.activeProviderId
        : (providers.isNotEmpty ? providers.first.id : '');

    final meta = <String, dynamic>{
      'activeProviderId': activeId,
      'providers': providers.map((p) => p.toJsonMeta()).toList(),
    };
    if (!await prefs.setString(prefsMetaKey, jsonEncode(meta))) {
      try { await prefs.reload(); } catch (_) {}
      throw StateError('提供商元数据保存失败');
    }

    final keys = <String, String>{};
    for (final p in providers) {
      final key = p.apiKey.trim();
      if (key.isNotEmpty) {
        keys[p.id] = key;
      }
    }
    // macOS Keychain 偶发弹窗/挂起；元数据已落 prefs，密钥写入限时，避免整页 UI 卡住。
    final pending = () async {
      await _writeSecureKeys(keys);
      final verified = await _readSecureKeys();
      if (verified.length != keys.length ||
          keys.entries.any((entry) => verified[entry.key] != entry.value)) {
        throw StateError('密钥存储校验失败');
      }
    }();
    _secureWriteInFlight = pending;
    // Observe eventual failure and clear the barrier only on actual completion.
    unawaited(pending.then<void>((_) {
      if (identical(_secureWriteInFlight, pending)) _secureWriteInFlight = null;
    }, onError: (Object _, StackTrace _) {
      if (identical(_secureWriteInFlight, pending)) _secureWriteInFlight = null;
    }));
    try {
      await pending.timeout(const Duration(seconds: 8));
    } on TimeoutException {
      throw StateError('密钥写入仍在处理中，元数据可能已保存；请稍后重新预览');
    } catch (_) {
      throw StateError('密钥保存未完成，元数据可能已保存');
    }

    // 若仍有明文残留（例如上次迁移失败后用户又保存了），在安全写入成功后清除。
    if (prefs.containsKey(keysStorageKey)) {
      try {
        await prefs.remove(keysStorageKey);
      } catch (_) {
        debugPrint(
          '[SecureProviderStorage] failed to clear legacy keys after save',
        );
      }
    }
    } finally {
      _saving = false;
    }
  }
}

/// 内存存储（单元测试 / 无插件环境）。
class MemoryProviderStorage implements ProviderStorage {
  MemoryProviderStorage([ProviderStoreSnapshot? initial])
      : _snapshot = initial ??
            ProviderStoreSnapshot(
              providers: builtinProviderPresets(),
              activeProviderId: builtinProviderPresets().first.id,
            );

  ProviderStoreSnapshot _snapshot;

  @override
  Future<ProviderStoreSnapshot> load() async => ProviderStoreSnapshot(
        providers: List<ProviderConfig>.from(_snapshot.providers),
        activeProviderId: _snapshot.activeProviderId,
      );

  @override
  Future<void> save(ProviderStoreSnapshot snapshot) async {
    _snapshot = ProviderStoreSnapshot(
      providers: List<ProviderConfig>.from(snapshot.providers),
      activeProviderId: snapshot.activeProviderId,
    );
  }
}
