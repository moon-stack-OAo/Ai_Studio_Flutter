import 'dart:async';
import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ControlledSecrets extends MemorySecretStore {
  int environmentWrites = 0;
  int? pauseEnvironmentAt;
  int? failEnvironmentAt;
  bool dropBearer = false;
  bool pauseBearer = false;
  final paused = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> write(String key, String value) async {
    if (key == mcpEnvironmentSecretKey('existing')) {
      environmentWrites++;
      if (environmentWrites == pauseEnvironmentAt) {
        paused.complete();
        await release.future;
      }
      if (environmentWrites == failEnvironmentAt) {
        throw StateError('RAW_SECRET_SENTINEL');
      }
    }
    if (pauseBearer && key == 'existing-ref') {
      paused.complete();
      await release.future;
    }
    if (dropBearer && key == 'existing-ref') return;
    await super.write(key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _ControlledSecrets secrets;
  late SharedPreferences prefs;
  late McpServerRepository mcp;
  late SkillRepository skills;
  late DataBackupService service;

  setUp(() async {
    secrets = _ControlledSecrets();
    final existing = McpServerConfig(
      id: 'existing',
      displayName: 'Existing',
      baseUrl: 'https://mcp.test',
      authKind: McpAuthKind.bearer,
      authSecretRef: 'existing-ref',
      env: const {'ENV': 'local-env'},
    );
    SharedPreferences.setMockInitialValues({
      PrefsMcpServerStorage.prefsKey: jsonEncode({
        'servers': [existing.toJsonMeta()],
      }),
    });
    await secrets.write(
      mcpEnvironmentSecretKey('existing'),
      jsonEncode(existing.env),
    );
    await secrets.write('existing-ref', 'local-bearer');
    secrets.environmentWrites = 0;
    prefs = await SharedPreferences.getInstance();
    mcp = McpServerRepository(
      storage: PrefsMcpServerStorage(prefs: prefs, secretStore: secrets),
      secretStore: secrets,
    );
    skills = SkillRepository(storage: MemorySkillStorage());
    service = DataBackupService(
      providers: ProviderRepository(
        storage: MemoryProviderStorage(),
        connectionTester: StubProviderConnectionTester(),
      ),
      appearance: AppearanceRepository(storage: MemoryAppearanceStorage()),
      chatDefaults: ChatDefaultsRepository(
        storage: MemoryChatDefaultsStorage(),
      ),
      chatSessions: ChatSessionRepository(storage: MemoryChatSessionStorage()),
      imageSessions: ImageSessionRepository(
        storage: MemoryImageSessionStorage(),
      ),
      videoSessions: VideoSessionRepository(
        storage: MemoryVideoSessionStorage(),
      ),
      logs: AppLogRepository(storage: MemoryAppLogStorage()),
      imageAssetStore: MemoryImageAssetStore(),
      videoAssetStore: MemoryVideoAssetStore(),
      mcpServers: mcp,
      skillRepository: skills,
    );
    await mcp.load();
    await skills.load();
  });

  Map<String, Object?> backup({bool includeSecrets = true}) => {
    'schemaVersion': dataBackupSchemaVersion,
    'exportedAtMs': 1,
    'includeSecrets': includeSecrets,
    'providers': {'activeProviderId': '', 'items': <Object>[]},
    'mcp': {
      'servers': [
        {
          'id': 'existing',
          'displayName': 'Updated',
          'baseUrl': 'https://mcp.test',
          'authKind': 'bearer',
          'authToken': 'import-bearer-1',
          'env': {'ENV': 'import-env-1'},
        },
        {
          'id': 'new',
          'displayName': 'New',
          'baseUrl': 'https://new.test',
          'authKind': 'bearer',
          'authToken': 'import-bearer-2',
          'env': {'ENV': 'import-env-2'},
        },
      ],
    },
    'skills': [
      const CustomSkill(
        id: 'next',
        name: 'Next',
        prompt: 'next stage',
        targets: {SkillTarget.image},
      ).toJson(),
    ],
  };

  void expectNoLeaks(Object error) {
    final journal = prefs.getString('core.backup_import_progress.v1') ?? '';
    for (final secret in [
      'RAW_SECRET_SENTINEL',
      'import-bearer-1',
      'import-bearer-2',
      'import-env-1',
    ]) {
      expect(error.toString(), isNot(contains(secret)));
      expect(journal, isNot(contains(secret)));
    }
  }

  test(
    'Prefs bearer import waits own slow save, preserves refs and runs skills',
    () async {
      secrets.pauseEnvironmentAt = 2;
      final plan = await service.prepareImport(
        backup(),
        options: const DataBackupImportOptions(importSecrets: true),
      );
      var finished = false;
      final applying = service
          .applyImport(plan)
          .whenComplete(() => finished = true);
      // Observe errors immediately as well, so the red case is deterministic.
      final observed = applying.then<Object>(
        (r) => r,
        onError: (Object e) => e,
      );
      await secrets.paused.future;
      await Future<void>.delayed(Duration.zero);
      final finishedWhileSaving = finished;
      expect(skills.skills, isEmpty);
      expect(mcp.hasPendingSecretWrites, isTrue);
      await expectLater(mcp.replaceAll(mcp.servers), throwsStateError);
      secrets.release.complete();
      final result = await observed;
      expect(finishedWhileSaving, isFalse);
      expect(result, isA<DataBackupImportResult>());
      expect((result as DataBackupImportResult).skillsImported, isTrue);
      expect(mcp.findById('existing')!.authSecretRef, 'existing-ref');
      expect(mcp.findById('new')!.authSecretRef, 'core.mcp.secret.new');
      expect(await mcp.readBearerSecret('existing'), 'import-bearer-1');
      expect(await mcp.readBearerSecret('new'), 'import-bearer-2');
      await mcp.load();
      expect(mcp.findById('existing')!.env, {'ENV': 'import-env-1'});
      expect(mcp.findById('new')!.env, {'ENV': 'import-env-2'});
      expect(skills.skills.single.id, 'next');
      expect(prefs.getString('core.backup_import_progress.v1'), isNull);
      expect(
        prefs.getString(PrefsMcpServerStorage.prefsKey),
        isNot(contains('import-bearer')),
      );
      expect(
        prefs.getString(PrefsMcpServerStorage.prefsKey),
        isNot(contains('import-env')),
      );
    },
  );

  test(
    'Prefs bearer import also drains metadata-only saves without env',
    () async {
      final raw = backup();
      final entries = (raw['mcp'] as Map)['servers'] as List;
      for (final entry in entries) {
        (entry as Map)['env'] = <String, String>{};
      }
      final plan = await service.prepareImport(
        raw,
        options: const DataBackupImportOptions(importSecrets: true),
      );
      final result = await service.applyImport(plan);
      expect(result.skillsImported, isTrue);
      expect(await mcp.readBearerSecret('existing'), 'import-bearer-1');
      expect(await mcp.readBearerSecret('new'), 'import-bearer-2');
      await mcp.load();
      expect(mcp.servers.every((s) => s.env.isEmpty), isTrue);
    },
  );

  for (final includeSecrets in [false, true]) {
    test('Prefs import secret opt-in include=$includeSecrets', () async {
      final plan = await service.prepareImport(
        backup(includeSecrets: includeSecrets),
        options: DataBackupImportOptions(importSecrets: !includeSecrets),
      );
      final result = await service.applyImport(plan);
      expect(result.skillsImported, isTrue);
      expect(await mcp.readBearerSecret('existing'), 'local-bearer');
      expect(await mcp.readBearerSecret('new'), isNull);
      await mcp.load();
      expect(mcp.findById('existing')!.env, {'ENV': 'local-env'});
      expect(mcp.findById('new')!.env, isEmpty);
    });
  }

  test(
    'Prefs own queued save failure cannot be masked by a later save',
    () async {
      secrets.failEnvironmentAt = 2;
      final plan = await service.prepareImport(
        backup(),
        options: const DataBackupImportOptions(importSecrets: true),
      );
      try {
        await service.applyImport(plan);
        fail('expected failure');
      } on DataBackupImportFailure catch (e) {
        expect(e.completed, contains('MCP 配置'));
        expect(e.completed, isNot(contains('MCP 密钥 1/2')));
        expect(e.failedStage, contains('MCP 密钥 1/2'));
        expect(e.notAttempted, contains('技能'));
        expectNoLeaks(e);
      }
      expect(skills.skills, isEmpty);
      expect(mcp.lastError, isNotNull);
    },
  );

  test('Prefs bearer readback mismatch fails without leaking token', () async {
    secrets.dropBearer = true;
    final plan = await service.prepareImport(
      backup(),
      options: const DataBackupImportOptions(importSecrets: true),
    );
    await expectLater(
      service.applyImport(plan),
      throwsA(
        isA<DataBackupImportFailure>().having(
          (e) {
            expectNoLeaks(e);
            return e.failedStage;
          },
          'failed stage',
          contains('MCP 密钥 1/2'),
        ),
      ),
    );
    expect(skills.skills, isEmpty);
  });

  for (final bearerTimeout in [false, true]) {
    test(
      'Prefs ${bearerTimeout ? 'bearer' : 'own save'} timeout keeps external pending barrier until underlying completion',
      () async {
        if (bearerTimeout) {
          secrets.pauseBearer = true;
        } else {
          secrets.pauseEnvironmentAt = 2;
        }
        final plan = await service.prepareImport(
          backup(),
          options: const DataBackupImportOptions(importSecrets: true),
        );
        final observed = service
            .applyImport(plan)
            .then<Object>((r) => r, onError: (Object e) => e);
        await secrets.paused.future;
        final failure = await observed;
        expect(failure, isA<DataBackupImportFailure>());
        expectNoLeaks(failure);
        expect(mcp.hasPendingSecretWrites, isTrue);
        await expectLater(mcp.replaceAll(mcp.servers), throwsStateError);
        await expectLater(mcp.load(), throwsStateError);
        await expectLater(service.prepareImport(backup()), throwsStateError);
        expect(skills.skills, isEmpty);
        secrets.release.complete();
        await Future<void>.delayed(Duration.zero);
        expect(mcp.hasPendingSecretWrites, isFalse);
      },
    );
  }
}
