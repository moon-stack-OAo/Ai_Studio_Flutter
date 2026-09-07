import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemorySecretStore secrets;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    secrets = MemorySecretStore();
  });

  ProviderConfig customProvider({
    required String id,
    required String apiKey,
  }) {
    return ProviderConfig(
      id: id,
      name: 'Custom',
      type: ProviderType.openai,
      baseUrl: 'https://api.example.local/v1',
      apiKey: apiKey,
      chatModel: 'gpt-test',
      builtin: false,
    );
  }

  test('save writes keys only to secret store, not prefs', () async {
    final storage = SecureProviderStorage(
      prefs: prefs,
      secretStore: secrets,
    );
    final snap = ProviderStoreSnapshot(
      providers: [customProvider(id: 'c1', apiKey: 'sk-secret-1')],
      activeProviderId: 'c1',
    );
    await storage.save(snap);

    expect(prefs.getString(SecureProviderStorage.keysStorageKey), isNull);
    expect(prefs.getString(SecureProviderStorage.prefsMetaKey), isNotNull);
    final raw = await secrets.read(SecureProviderStorage.keysStorageKey);
    expect(raw, isNotNull);
    final map = jsonDecode(raw!) as Map<String, dynamic>;
    expect(map['c1'], 'sk-secret-1');

    final loaded = await storage.load();
    expect(loaded.providers.single.apiKey, 'sk-secret-1');
  });

  test('migrates plaintext prefs keys then clears legacy', () async {
    final meta = {
      'activeProviderId': 'c1',
      'providers': [
        customProvider(id: 'c1', apiKey: '').toJsonMeta(),
      ],
    };
    await prefs.setString(
      SecureProviderStorage.prefsMetaKey,
      jsonEncode(meta),
    );
    await prefs.setString(
      SecureProviderStorage.keysStorageKey,
      jsonEncode({'c1': 'sk-legacy'}),
    );

    final storage = SecureProviderStorage(
      prefs: prefs,
      secretStore: secrets,
    );
    final loaded = await storage.load();

    expect(loaded.providers.single.apiKey, 'sk-legacy');
    expect(prefs.getString(SecureProviderStorage.keysStorageKey), isNull);
    expect(
      secrets.debugData[SecureProviderStorage.keysStorageKey],
      contains('sk-legacy'),
    );
    expect(storage.lastMigrationNote, contains('migrated'));
  });

  test('migration failure keeps plaintext prefs', () async {
    await prefs.setString(
      SecureProviderStorage.prefsMetaKey,
      jsonEncode({
        'activeProviderId': 'c1',
        'providers': [customProvider(id: 'c1', apiKey: '').toJsonMeta()],
      }),
    );
    await prefs.setString(
      SecureProviderStorage.keysStorageKey,
      jsonEncode({'c1': 'sk-keep-me'}),
    );

    final storage = SecureProviderStorage(
      prefs: prefs,
      secretStore: _FailingWriteSecretStore(),
    );
    final loaded = await storage.load();

    expect(loaded.providers.single.apiKey, 'sk-keep-me');
    expect(
      prefs.getString(SecureProviderStorage.keysStorageKey),
      isNotNull,
      reason: '失败安全：不得静默清空明文',
    );
    expect(storage.lastMigrationNote, contains('migration failed'));
  });

  test('secure keys win over legacy on id conflict', () async {
    await prefs.setString(
      SecureProviderStorage.prefsMetaKey,
      jsonEncode({
        'activeProviderId': 'c1',
        'providers': [customProvider(id: 'c1', apiKey: '').toJsonMeta()],
      }),
    );
    await prefs.setString(
      SecureProviderStorage.keysStorageKey,
      jsonEncode({'c1': 'sk-old'}),
    );
    await secrets.write(
      SecureProviderStorage.keysStorageKey,
      jsonEncode({'c1': 'sk-new'}),
    );

    final storage = SecureProviderStorage(
      prefs: prefs,
      secretStore: secrets,
    );
    final loaded = await storage.load();
    expect(loaded.providers.single.apiKey, 'sk-new');
    expect(prefs.getString(SecureProviderStorage.keysStorageKey), isNull);
  });

  test('empty apiKey is omitted from secret map', () async {
    final storage = SecureProviderStorage(
      prefs: prefs,
      secretStore: secrets,
    );
    await storage.save(
      ProviderStoreSnapshot(
        providers: [
          customProvider(id: 'c1', apiKey: '  '),
          customProvider(id: 'c2', apiKey: 'sk-ok'),
        ],
        activeProviderId: 'c2',
      ),
    );
    final raw = await secrets.read(SecureProviderStorage.keysStorageKey);
    final map = jsonDecode(raw!) as Map<String, dynamic>;
    expect(map.containsKey('c1'), isFalse);
    expect(map['c2'], 'sk-ok');
  });
}

/// 写入即失败，用于验证迁移失败安全。
class _FailingWriteSecretStore implements SecretStore {
  @override
  Future<bool> containsKey(String key) async => false;

  @override
  Future<void> delete(String key) async {}

  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {
    throw StateError('simulated secure write failure');
  }
}
