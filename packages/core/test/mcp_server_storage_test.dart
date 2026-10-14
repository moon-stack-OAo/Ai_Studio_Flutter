import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailingEnvironmentStore extends MemorySecretStore {
  _FailingEnvironmentStore({required this.failWrite});
  final bool failWrite;

  @override
  Future<void> write(String key, String value) async {
    if (failWrite) throw StateError('test secure write failed');
    await super.write(key, value);
  }

  @override
  Future<String?> read(String key) async =>
      failWrite ? super.read(key) : 'corrupt-read';
}

void main() {
  group('PrefsMcpServerStorage + repository secrets', () {
    late SharedPreferences prefs;
    late MemorySecretStore secrets;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      secrets = MemorySecretStore();
    });

    test('persist meta without token; bearer in SecretStore', () async {
      final storage = PrefsMcpServerStorage(prefs: prefs);
      final repo = McpServerRepository(storage: storage, secretStore: secrets);
      await repo.load();
      final id = await repo.add(
        displayName: 'Biz',
        baseUrl: 'https://mcp.local/mcp',
        authKind: McpAuthKind.bearer,
        bearerToken: 'tok-plain-xyz',
      );
      await repo.waitForPersist();
      final raw = prefs.getString(PrefsMcpServerStorage.prefsKey)!;
      expect(raw, isNot(contains('tok-plain-xyz')));
      expect(raw, contains(id));

      final ref = repo.findById(id)!.authSecretRef!;
      expect(await secrets.read(ref), 'tok-plain-xyz');

      expect(await repo.hasBearerSecret(id), isTrue);

      final again = McpServerRepository(
        storage: PrefsMcpServerStorage(prefs: prefs),
        secretStore: secrets,
      );
      await again.load();
      expect(again.servers, hasLength(1));
      expect(again.servers.single.authKind, McpAuthKind.bearer);
      expect(again.servers.single.authSecretRef, ref);
      expect(await secrets.read(ref), 'tok-plain-xyz');
    });

    test(
      'environment is secure, reloads, and secrets-only clearing removes it',
      () async {
        final repo = McpServerRepository(
          storage: PrefsMcpServerStorage(prefs: prefs, secretStore: secrets),
          secretStore: secrets,
        );
        await repo.load();
        final id = await repo.add(
          displayName: 'Local',
          transport: McpTransport.stdio,
          command: 'node',
          env: {'API_KEY': 'env-secret-value', 'DEBUG': '1'},
          stdioConfirmed: true,
        );
        await repo.waitForPersist();
        expect(repo.lastError, isNull);
        expect(
          prefs.getString(PrefsMcpServerStorage.prefsKey),
          isNot(contains('env-secret-value')),
        );
        expect(
          await secrets.read(mcpEnvironmentSecretKey(id)),
          contains('env-secret-value'),
        );
        final restored = await PrefsMcpServerStorage(
          prefs: prefs,
          secretStore: secrets,
        ).load();
        expect(restored.servers.single.env, {
          'API_KEY': 'env-secret-value',
          'DEBUG': '1',
        });
        expect(restored.servers.single.isStdioApproved, isTrue);
        await repo.clearAllSecrets();
        expect(repo.servers.single.env, isEmpty);
        expect(repo.servers.single.enabled, isFalse);
        expect(await secrets.read(mcpEnvironmentSecretKey(id)), isNull);
        final cleared = await PrefsMcpServerStorage(
          prefs: prefs,
          secretStore: secrets,
        ).load();
        expect(cleared.servers.single.env, isEmpty);
        expect(secrets.debugData, isEmpty);
      },
    );

    test(
      'legacy env migrates after verified secure write and requires confirmation',
      () async {
        await prefs.setString(
          PrefsMcpServerStorage.prefsKey,
          jsonEncode({
            'servers': [
              {
                'id': 'legacy',
                'displayName': 'Local',
                'transport': 'stdio',
                'command': 'node',
                'env': {'TOKEN': 'legacy-secret'},
                'enabled': true,
              },
            ],
          }),
        );
        final snapshot = await PrefsMcpServerStorage(
          prefs: prefs,
          secretStore: secrets,
        ).load();
        expect(snapshot.servers.single.env, {'TOKEN': 'legacy-secret'});
        expect(snapshot.servers.single.enabled, isFalse);
        expect(
          await secrets.read(mcpEnvironmentSecretKey('legacy')),
          contains('legacy-secret'),
        );
        expect(
          prefs.getString(PrefsMcpServerStorage.prefsKey),
          isNot(contains('legacy-secret')),
        );
      },
    );

    for (final failWrite in [true, false]) {
      test(
        'migration preserves plaintext when ${failWrite ? 'write' : 'readback'} fails',
        () async {
          final original = jsonEncode({
            'servers': [
              {
                'id': 'legacy',
                'displayName': 'Local',
                'transport': 'stdio',
                'command': 'node',
                'env': {'TOKEN': 'legacy-secret'},
              },
            ],
          });
          await prefs.setString(PrefsMcpServerStorage.prefsKey, original);
          final storage = PrefsMcpServerStorage(
            prefs: prefs,
            secretStore: _FailingEnvironmentStore(failWrite: failWrite),
          );
          await expectLater(storage.load(), throwsStateError);
          expect(prefs.getString(PrefsMcpServerStorage.prefsKey), original);
        },
      );
    }

    test(
      'configuration changes revoke command approval and delete cleans env',
      () async {
        final repo = McpServerRepository(
          storage: PrefsMcpServerStorage(prefs: prefs, secretStore: secrets),
          secretStore: secrets,
        );
        await repo.load();
        final id = await repo.add(
          displayName: 'Local',
          transport: McpTransport.stdio,
          command: 'node',
          env: {'TOKEN': 'delete-me'},
          stdioConfirmed: true,
        );
        await repo.waitForPersist();
        await repo.update(repo.findById(id)!.copyWith(args: ['changed.js']));
        expect(repo.findById(id)!.enabled, isFalse);
        expect(repo.findById(id)!.isStdioApproved, isFalse);
        await repo.setEnabled(id, true);
        expect(repo.findById(id)!.enabled, isFalse);
        await repo.update(
          repo.findById(id)!.copyWith(enabled: true),
          stdioConfirmed: true,
        );
        expect(repo.enabledServers, hasLength(1));
        await repo.delete(id);
        expect(secrets.debugData, isEmpty);
        expect(
          (await PrefsMcpServerStorage(
            prefs: prefs,
            secretStore: secrets,
          ).load())
              .servers,
          isEmpty,
        );
      },
    );

    test('delete removes secret', () async {
      final repo = McpServerRepository(
        storage: PrefsMcpServerStorage(prefs: prefs),
        secretStore: secrets,
      );
      await repo.load();
      final id = await repo.add(
        displayName: 'A',
        baseUrl: 'https://a.local/mcp',
        authKind: McpAuthKind.bearer,
        bearerToken: 'secret',
      );
      await repo.waitForPersist();
      final ref = repo.findById(id)!.authSecretRef!;
      await repo.delete(id);
      await repo.waitForPersist();
      expect(await secrets.read(ref), isNull);
      expect(repo.servers, isEmpty);
    });

    test('clearAllSecrets keeps meta; clearAllServers wipes list', () async {
      final repo = McpServerRepository(
        storage: PrefsMcpServerStorage(prefs: prefs),
        secretStore: secrets,
      );
      await repo.load();
      final id = await repo.add(
        displayName: 'B',
        baseUrl: 'https://b.local/mcp',
        authKind: McpAuthKind.bearer,
        bearerToken: 'tok-b',
      );
      await repo.waitForPersist();
      final ref = repo.findById(id)!.authSecretRef!;
      await repo.clearAllSecrets();
      expect(repo.servers, hasLength(1));
      expect(await secrets.read(ref), isNull);
      expect(await repo.hasBearerSecret(id), isFalse);

      await repo.writeBearerSecret(id, 'tok-b2');
      await repo.waitForPersist();
      await repo.clearAllServers();
      expect(repo.servers, isEmpty);
      expect(await secrets.read(ref), isNull);
    });
  });

  group('mcpToolsToOpenAiTools', () {
    test('maps descriptors', () {
      final tools = mcpToolsToOpenAiTools(const [
        McpToolDescriptor(
          name: 'biz.query',
          description: '查询',
          inputSchemaSummary: '{"type":"object"}',
        ),
        McpToolDescriptor(name: 'biz.query'), // dedupe
      ]);
      expect(tools, hasLength(1));
      expect(tools.single['type'], 'function');
      expect((tools.single['function'] as Map)['name'], 'biz.query');
    });
  });
}
