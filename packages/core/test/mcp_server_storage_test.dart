import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      final repo = McpServerRepository(
        storage: storage,
        secretStore: secrets,
      );
      await repo.load();
      final id = await repo.add(
        displayName: 'Biz',
        baseUrl: 'https://mcp.local/mcp',
        authKind: McpAuthKind.bearer,
        bearerToken: 'tok-plain-xyz',
      );
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
      final ref = repo.findById(id)!.authSecretRef!;
      await repo.delete(id);
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
      final ref = repo.findById(id)!.authSecretRef!;
      await repo.clearAllSecrets();
      expect(repo.servers, hasLength(1));
      expect(await secrets.read(ref), isNull);
      expect(await repo.hasBearerSecret(id), isFalse);

      await repo.writeBearerSecret(id, 'tok-b2');
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
      expect(
        (tools.single['function'] as Map)['name'],
        'biz.query',
      );
    });
  });
}
