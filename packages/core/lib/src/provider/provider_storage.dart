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
        _secrets = secretStore ?? FlutterSecureSecretStore();

  /// 元数据 prefs 键。
  static const prefsMetaKey = 'core.providers.v1';

  /// 密钥映射键（安全存储与旧版明文 prefs 同名，便于迁移识别）。
  static const keysStorageKey = 'core.provider.keys.v1';

  final SharedPreferences? _prefsOverride;
  final SecretStore _secrets;
  SharedPreferences? _prefs;

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
      } catch (e) {
        lastMigrationNote = 'failed to clear empty legacy keys: $e';
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
    } catch (e) {
      lastMigrationNote =
          'migration failed; plaintext prefs keys retained: $e';
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
    final prefs = await _ensurePrefs();
    final providers = snapshot.providers;
    final activeId = providers.any((p) => p.id == snapshot.activeProviderId)
        ? snapshot.activeProviderId
        : (providers.isNotEmpty ? providers.first.id : '');

    final meta = <String, dynamic>{
      'activeProviderId': activeId,
      'providers': providers.map((p) => p.toJsonMeta()).toList(),
    };
    await prefs.setString(prefsMetaKey, jsonEncode(meta));

    final keys = <String, String>{};
    for (final p in providers) {
      final key = p.apiKey.trim();
      if (key.isNotEmpty) {
        keys[p.id] = key;
      }
    }
    await _writeSecureKeys(keys);

    // 若仍有明文残留（例如上次迁移失败后用户又保存了），在安全写入成功后清除。
    if (prefs.containsKey(keysStorageKey)) {
      try {
        await prefs.remove(keysStorageKey);
      } catch (e) {
        debugPrint(
          '[SecureProviderStorage] failed to clear legacy keys after save: $e',
        );
      }
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
