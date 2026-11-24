import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailingAppearance extends MemoryAppearanceStorage {
  @override
  Future<void> save(AppearanceSettings settings) async => throw StateError('SENSITIVE_SENTINEL');
}

class _FailingSkills extends MemorySkillStorage {
  bool damaged = false;
  @override
  Future<List<CustomSkill>> load() async {
    if (damaged) throw SkillStorageFormatException('损坏', []);
    return super.load();
  }
  @override
  Future<void> save(List<CustomSkill> skills) async => throw StateError('SENSITIVE_SENTINEL');
}

class _PausedAppearance extends MemoryAppearanceStorage {
  final gate = Completer<void>();
  @override
  Future<void> save(AppearanceSettings settings) async {
    await gate.future;
    await super.save(settings);
  }
}

void main() {
  late ProviderRepository providers;
  late AppearanceRepository appearance;
  late ChatDefaultsRepository chatDefaults;
  late ChatSessionRepository chatSessions;
  late ImageSessionRepository imageSessions;
  late VideoSessionRepository videoSessions;
  late AppLogRepository logs;
  late MemoryImageAssetStore imageStore;
  late MemoryVideoAssetStore videoStore;
  late MemorySecretStore mcpSecrets;
  late McpServerRepository mcpServers;
  late DataBackupService service;
  late SkillRepository skills;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    providers = ProviderRepository(
      storage: MemoryProviderStorage(),
      connectionTester: StubProviderConnectionTester(),
    );
    appearance = AppearanceRepository(storage: MemoryAppearanceStorage());
    chatDefaults = ChatDefaultsRepository(storage: MemoryChatDefaultsStorage());
    chatSessions = ChatSessionRepository(storage: MemoryChatSessionStorage());
    imageStore = MemoryImageAssetStore();
    videoStore = MemoryVideoAssetStore();
    imageSessions = ImageSessionRepository(
      storage: MemoryImageSessionStorage(),
      assetStore: imageStore,
    );
    videoSessions = VideoSessionRepository(
      storage: MemoryVideoSessionStorage(),
      assetStore: videoStore,
    );
    logs = AppLogRepository(storage: MemoryAppLogStorage());
    mcpSecrets = MemorySecretStore();
    mcpServers = McpServerRepository(
      storage: MemoryMcpServerStorage(),
      secretStore: mcpSecrets,
    );

    await providers.load();
    await appearance.load();
    await chatDefaults.load();
    await chatSessions.load();
    await imageSessions.load();
    await videoSessions.load();
    await logs.load();
    await mcpServers.load();
    skills = SkillRepository(storage: MemorySkillStorage());
    await skills.load();

    service = DataBackupService(
      providers: providers,
      appearance: appearance,
      chatDefaults: chatDefaults,
      chatSessions: chatSessions,
      imageSessions: imageSessions,
      videoSessions: videoSessions,
      logs: logs,
      imageAssetStore: imageStore,
      videoAssetStore: videoStore,
      mcpServers: mcpServers,
      skillRepository: skills,
    );
  });

  test('preview is read-only, multiline, bound to baseline and single-use', () async {
    final raw = await service.exportBackupJson();
    final before = await service.exportBackupJson();
    final plan = await service.prepareImport(raw);
    expect(plan.summary, contains(String.fromCharCode(10)));
    expect(plan.summary, contains('仅元数据'));
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    expect(jsonDecode(await service.exportBackupJson())['providers'], jsonDecode(before)['providers']);
    await appearance.update(themePreference: 'dark');
    await expectLater(service.applyImport(plan), throwsA(isA<DataBackupFormatException>()));
    final confirmed = await service.prepareImport(raw);
    await service.applyImport(confirmed);
    await expectLater(service.applyImport(confirmed), throwsA(isA<DataBackupFormatException>()));
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
  });

  test('malformed known blocks and rows reject before any progress or writes', () async {
    final original = jsonDecode(await service.exportBackupJson()) as Map<String, dynamic>;
    for (final change in <Map<String, dynamic>>[
      {'chat': {}}, {'image': {'sessions': [7]}}, {'video': null},
      {'providers': {'items': [{'id': 'bad', 'baseUrl': 'https://a.test', 'enabled': 'yes'}]}},
      {'mcp': {'servers': [{'id': 'bad', 'args': [12]}]}},
      {'schemaVersion': 1.9},
    ]) {
      await expectLater(service.importBackup({...original, ...change}), throwsA(anyOf(isA<DataBackupFormatException>(), isA<DataBackupSchemaException>())));
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    }
  });

  test('forged plan cannot write and payload mutation cannot replace prepared content', () async {
    final raw = await service.exportBackupJson();
    final plan = await service.prepareImport(raw);
    final fake = DataBackupImportPlan(payload: plan.payload, options: plan.options, baseline: plan.baseline, summary: plan.summary);
    await expectLater(service.applyImport(fake), throwsA(isA<DataBackupFormatException>()));
    plan.payload.providers.clear();
    await service.applyImport(plan);
    expect(providers.providers, isNotEmpty);
  });

  test('credential-only changes invalidate preview and journal restart never replays', () async {
    final id = await mcpServers.add(displayName: 'server', baseUrl: 'https://mcp.test', authKind: McpAuthKind.bearer, bearerToken: 'old');
    final plan = await service.prepareImport(await service.exportBackupJson());
    await mcpServers.writeBearerSecret(id, 'new');
    await expectLater(service.applyImport(plan), throwsA(isA<DataBackupFormatException>()));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('core.backup_import_progress.v1', '{"stage":"提供商"}');
    await service.loadImportStatus();
    expect(service.importRecoverySummary, contains('不会自动重放或回滚'));
    expect(await mcpServers.readBearerSecret(id), 'new');
  });

  DataBackupService withAppearance(AppearanceRepository repository) => DataBackupService(
    providers: providers, appearance: repository, chatDefaults: chatDefaults,
    chatSessions: chatSessions, imageSessions: imageSessions, videoSessions: videoSessions,
    logs: logs, imageAssetStore: imageStore, videoAssetStore: videoStore,
    mcpServers: mcpServers, skillRepository: skills,
  );

  test('partial failure reports completed unknown unattempted without plugin details', () async {
    final broken = AppearanceRepository(storage: _FailingAppearance());
    await broken.load();
    final importing = withAppearance(broken);
    final raw = await service.exportBackupJson();
    final plan = await importing.prepareImport(raw);
    try {
      await importing.applyImport(plan);
      fail('expected partial failure');
    } on DataBackupImportFailure catch (e) {
      expect(e.completed, ['提供商']);
      expect(e.failedStage, contains('外观 写入结果未知'));
      expect(e.notAttempted, contains('对话历史'));
      expect(e.businessWritesComplete, isFalse);
      expect(e.toString(), isNot(contains('SENSITIVE_SENTINEL')));
    }
    final journal = (await SharedPreferences.getInstance()).getString('core.backup_import_progress.v1')!;
    expect(journal, isNot(contains('SENSITIVE_SENTINEL')));
    await importing.loadImportStatus();
    expect(importing.importRecoverySummary, contains('不会自动重放'));
  });

  test('preview waits queued appearance before capturing baseline', () async {
    final storage = _PausedAppearance();
    final repository = AppearanceRepository(storage: storage);
    await repository.load();
    final importing = withAppearance(repository);
    final saving = repository.save(repository.settings.copyWith(themePreference: 'dark'));
    var done = false;
    final preview = importing.prepareImport(await service.exportBackupJson()).then((p) { done = true; return p; });
    await Future<void>.delayed(Duration.zero);
    expect(done, isFalse);
    storage.gate.complete();
    await saving;
    final plan = await preview;
    expect(repository.settings.themePreference, 'dark');
    await importing.applyImport(plan);
  });

  test('known damaged skills prevent prepare and later-stage failure preserves old assets', () async {
    final storage = _FailingSkills()..damaged = true;
    final repository = SkillRepository(storage: storage);
    await repository.load();
    final importing = DataBackupService(
      providers: providers, appearance: appearance, chatDefaults: chatDefaults,
      chatSessions: chatSessions, imageSessions: imageSessions, videoSessions: videoSessions,
      logs: logs, imageAssetStore: imageStore, videoAssetStore: videoStore,
      mcpServers: mcpServers, skillRepository: repository,
    );
    final empty = await service.exportBackupJson();
    await expectLater(importing.prepareImport(empty), throwsA(isA<DataBackupFormatException>()));
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    final cleanRepository = SkillRepository(storage: _FailingSkills());
    await cleanRepository.load();
    final partial = DataBackupService(
      providers: providers, appearance: appearance, chatDefaults: chatDefaults,
      chatSessions: chatSessions, imageSessions: imageSessions, videoSessions: videoSessions,
      logs: logs, imageAssetStore: imageStore, videoAssetStore: videoStore,
      mcpServers: mcpServers, skillRepository: cleanRepository,
    );
    final image = await imageSessions.createSession(title: 'old');
    await imageSessions.appendLoadingItem(image.id, mode: ImageGenMode.text, prompt: 'old', model: 'm');
    final path = await imageStore.savePng(Uint8List.fromList([1, 2]), 'old');
    await imageSessions.completeItem(image.id, imageSessions.activeSession!.items.last.id, [ImageRef(type: ImageRefType.file, src: path)]);
    final plan = await partial.prepareImport(empty);
    await expectLater(partial.applyImport(plan), throwsA(isA<DataBackupImportFailure>().having((e) => e.failedStage, 'skills stage', contains('技能'))));
    expect(imageSessions.sessions.any((s) => s.id == image.id), isFalse);
    expect(await imageStore.read(path), isNotNull);
  });

  Future<void> seedSampleData() async {
    await appearance.update(themePreference: 'dark', fontScale: 'large');
    await chatDefaults.update(temperature: 0.7, systemPrompt: 'hi');
    final custom = await providers.addProvider(
      name: 'BackupMe',
      baseUrl: 'https://api.backup.test/v1',
      apiKey: 'sk-secret-backup',
      chatModel: 'gpt-test',
      imageModel: 'img-test',
    );
    await providers.setActiveProvider(custom.id);

    await mcpServers.add(
      displayName: 'Biz MCP',
      baseUrl: 'https://mcp.backup.test/mcp',
      authKind: McpAuthKind.bearer,
      bearerToken: 'mcp-tok-backup-xyz',
    );

    final chat = await chatSessions.createSession(title: '导出对话');
    await chatSessions.appendMessage(
      chat.id,
      role: ChatRole.user,
      content: '你好',
    );

    final img = await imageSessions.createSession(title: '导出生图');
    await imageSessions.appendLoadingItem(
      img.id,
      mode: ImageGenMode.text,
      prompt: '一只猫',
      model: 'img-test',
    );
    final imgItem = imageSessions.activeSession!.items.last;
    final path = await imageStore.savePng(
      Uint8List.fromList([1, 2, 3, 4]),
      'seed_img',
    );
    await imageSessions.completeItem(img.id, imgItem.id, [
      ImageRef(type: ImageRefType.file, src: path),
    ]);

    await logs.append(level: AppLogLevel.info, source: 'test', message: 'seed');
  }

  test('导出与导入共用真实字符边界，包含 pretty 开销且不按 UTF-8 字节限制', () async {
    for (final pretty in [false, true]) {
      await chatDefaults.update(systemPrompt: '');
      final emptyJson = await service.exportBackupJson(
        const DataBackupExportOptions(),
        pretty,
      );
      final overhead = emptyJson.length;
      final baseUtf8Extra = utf8.encode(emptyJson).length - overhead;
      // 中占 1 个 UTF-16 代码单元，😀占 2 个；UTF-8 合计则是 7 字节。
      final prompt = '中😀${'x' * (maxBackupJsonChars - overhead - 3)}';
      await chatDefaults.update(systemPrompt: prompt);
      final json = await service.exportBackupJson(
        const DataBackupExportOptions(),
        pretty,
      );
      expect(json.length, maxBackupJsonChars);
      expect(utf8.encode(json).length, maxBackupJsonChars + baseUtf8Extra + 4);
      expect(
        DataBackupPayload.parse(' \n$json\n ').chatDefaults!.systemPrompt,
        prompt,
      );
      if (!pretty) {
        // 紧凑格式刚好可导回时，默认缩进格式可能已超限，不能静默改格式。
        await expectLater(
          service.exportBackupJson(),
          throwsA(isA<DataBackupFormatException>()),
        );
      }
      await chatDefaults.update(systemPrompt: '${prompt}x');
      final payload = await service.exportBackup();
      final uncheckedJson = pretty
          ? const JsonEncoder.withIndent('  ').convert(payload.toJson())
          : jsonEncode(payload.toJson());
      expect(uncheckedJson.length, maxBackupJsonChars + 1);
      expect(
        () => DataBackupPayload.parse(uncheckedJson),
        throwsA(isA<DataBackupFormatException>()),
      );
      expect(
        () => payload.encodeJson(pretty: pretty),
        throwsA(
          isA<DataBackupFormatException>().having(
            (e) => e.message,
            '安全明确错误，不回显备份内容',
            '备份超过 $maxBackupJsonChars 字符（UTF-16 代码单元）的导入上限，已停止导出',
          ),
        ),
      );
      await expectLater(
        service.exportBackupJson(const DataBackupExportOptions(), pretty),
        throwsA(isA<DataBackupFormatException>()),
      );
      expect(chatDefaults.defaults.systemPrompt, '${prompt}x');
    }
  });

  test('技能 backup roundtrip、原位合并、新 ID 按顺序追加、用量估算', () async {
    const a = CustomSkill(
      id: 'a',
      name: 'A',
      prompt: '技能A',
      targets: {SkillTarget.image},
    );
    const b = CustomSkill(
      id: 'b',
      name: 'B',
      rules: '技能B',
      targets: {SkillTarget.video},
    );
    await skills.replaceAll([a, b]);
    final usage = await service.estimateStorageUsage();
    expect(usage.skillCount, 2);
    final json = await service.exportBackupJson();
    final parsed = DataBackupPayload.parse(json);
    expect(parsed.skills!.map((s) => s.toJson()).toList(), [
      a.toJson(),
      b.toJson(),
    ]);
    await service.clearLocalData(ClearLocalDataFlags.all);
    expect(skills.skills, isEmpty);
    final result = await service.importBackup(json);
    expect(result.skillsImported, isTrue);
    expect(result.skillsAdded, 2);
    expect(skills.skills.map((s) => s.id), ['a', 'b']);
    await skills.replaceAll([
      b.copyWith(name: '本地B'),
      a,
      a.copyWith(id: 'local'),
    ]);
    final imported = await service.importBackup(json);
    expect(imported.skillsMerged, 2);
    expect(skills.skills.map((s) => s.id), ['b', 'a', 'local']);
    expect(skills.skills.first.name, 'B');
    final incoming = parsed.toJson();
    incoming['skills'] = [
      a.toJson(),
      a.copyWith(id: 'new2').toJson(),
      a.copyWith(id: 'new1').toJson(),
    ];
    final appended = await service.importBackup(incoming);
    expect(appended.skillsAdded, 2);
    expect(skills.skills.map((s) => s.id), ['b', 'a', 'local', 'new2', 'new1']);
    await skills.clear();
    final without = await service.estimateStorageUsage();
    expect(usage.approxJsonBytes, greaterThan(without.approxJsonBytes));
  });

  test('旧备份与导入导出开关保留本地技能，空技能段按合并语义处理', () async {
    const local = CustomSkill(
      id: 'local',
      name: '本地',
      rules: '限制',
      targets: {SkillTarget.chat},
    );
    await skills.saveSkill(local);
    final omitted = await service.exportBackup(
      const DataBackupExportOptions(includeSkills: false),
    );
    expect(omitted.skills, isNull);
    expect(omitted.toJson().containsKey('skills'), isFalse);
    final oldResult = await service.importBackup(omitted.encodeJson());
    expect(oldResult.skillsImported, isFalse);
    expect(skills.skills.single.id, 'local');
    final included = (await service.exportBackup()).toJson();
    included['skills'] = [local.copyWith(id: 'incoming').toJson()];
    final disabledResult = await service.importBackup(
      included,
      options: const DataBackupImportOptions(importSkills: false),
    );
    expect(disabledResult.skillsImported, isFalse);
    expect(skills.skills.single.id, 'local');
    included['skills'] = [];
    await service.importBackup(included);
    expect(skills.skills.single.id, 'local');
  });

  test('仅清 settings/all 清技能，providers/sessions/media 保留技能', () async {
    const skill = CustomSkill(
      id: 'a',
      name: 'A',
      rules: '限制',
      targets: {SkillTarget.image},
    );
    await skills.saveSkill(skill);
    for (final flags in [
      const ClearLocalDataFlags(providers: true),
      ClearLocalDataFlags.sessionsOnly,
      ClearLocalDataFlags.mediaOnly,
    ]) {
      await service.clearLocalData(flags);
      expect(skills.skills.single.id, 'a');
    }
    await service.clearLocalData(const ClearLocalDataFlags(settings: true));
    expect(skills.skills, isEmpty);
  });

  test('技能损坏备份在修改本地数据前拒绝', () async {
    const local = CustomSkill(
      id: 'local',
      name: '本地',
      rules: '限制',
      targets: {SkillTarget.chat},
    );
    await skills.saveSkill(local);
    final payload = (await service.exportBackup()).toJson();
    payload['skills'] = [
      {'id': 'broken'},
    ];
    await expectLater(
      service.importBackup(payload),
      throwsA(isA<DataBackupFormatException>()),
    );
    expect(skills.skills.single.id, 'local');
  });

  test(
    'export → import roundtrip preserves appearance / providers / chat',
    () async {
      await seedSampleData();

      final json = await service.exportBackupJson();
      final payload = DataBackupPayload.parse(json);
      expect(payload.schemaVersion, dataBackupSchemaVersion);
      expect(payload.includeSecrets, isFalse);
      expect(payload.appearance?.themePreference, 'dark');
      expect(payload.chatSessions, isNotEmpty);

      // 清空后再导入
      await service.clearLocalData(ClearLocalDataFlags.all);

      final result = await service.importBackup(json);
      expect(result.appearanceImported, isTrue);
      expect(result.chatDefaultsImported, isTrue);
      expect(result.sessionsImported, isTrue);
      expect(result.secretsApplied, isFalse);

      expect(appearance.settings.themePreference, 'dark');
      expect(chatDefaults.defaults.temperature, 0.7);
      expect(providers.providers.any((p) => p.name == 'BackupMe'), isTrue);
      final restored = providers.providers.firstWhere(
        (p) => p.name == 'BackupMe',
      );
      expect(restored.apiKey, isEmpty); // 默认不含密钥
      expect(restored.baseUrl, 'https://api.backup.test/v1');
      expect(restored.chatModel, 'gpt-test');
      expect(chatSessions.sessions.any((s) => s.title == '导出对话'), isTrue);
    },
  );

  test('default export omits apiKey plaintext', () async {
    await seedSampleData();
    final json = await service.exportBackupJson();
    expect(json.contains('sk-secret-backup'), isFalse);
    expect(json.contains('"includeSecrets": false'), isTrue);

    final payload = DataBackupPayload.parse(json);
    for (final p in payload.providers) {
      expect(p.apiKey, isEmpty);
    }
  });

  test('includeSecrets=true exports and can re-import keys', () async {
    await seedSampleData();
    final json = await service.exportBackupJson(
      const DataBackupExportOptions(includeSecrets: true),
    );
    expect(json.contains('sk-secret-backup'), isTrue);
    expect(json.contains('"includeSecrets": true'), isTrue);

    await service.clearLocalData(ClearLocalDataFlags.all);

    final withoutSecrets = await service.importBackup(
      json,
      options: const DataBackupImportOptions(importSecrets: false),
    );
    expect(withoutSecrets.secretsApplied, isFalse);
    expect(
      providers.providers
          .where((p) => p.name == 'BackupMe')
          .every((p) => p.apiKey.isEmpty),
      isTrue,
    );

    final withSecrets = await service.importBackup(
      json,
      options: const DataBackupImportOptions(importSecrets: true),
    );
    expect(withSecrets.secretsApplied, isTrue);
    final p = providers.providers.firstWhere((e) => e.name == 'BackupMe');
    expect(p.apiKey, 'sk-secret-backup');
  });

  test('schema mismatch throws DataBackupSchemaException', () {
    expect(
      () => DataBackupPayload.parse({
        'schemaVersion': 999,
        'providers': {'activeProviderId': '', 'items': []},
      }),
      throwsA(isA<DataBackupSchemaException>()),
    );
  });

  test('malformed JSON throws DataBackupFormatException', () {
    expect(
      () => DataBackupPayload.parse('{not-json'),
      throwsA(isA<DataBackupFormatException>()),
    );
    expect(
      () => DataBackupPayload.parse('[]'),
      throwsA(isA<DataBackupFormatException>()),
    );
    expect(
      () => DataBackupPayload.parse({'providers': 'x'}),
      throwsA(isA<DataBackupFormatException>()),
    );
  });

  test(
    'mergeProviders: same id overwrites meta; secrets only when allowed',
    () {
      final local = [
        ProviderConfig(
          id: 'openai',
          name: 'OpenAI',
          type: ProviderType.openai,
          baseUrl: 'https://old',
          apiKey: 'sk-local',
          chatModel: 'old-model',
          builtin: true,
        ),
      ];
      final incoming = [
        ProviderConfig(
          id: 'openai',
          name: 'OpenAI Cloud',
          type: ProviderType.openai,
          baseUrl: 'https://new',
          apiKey: 'sk-incoming',
          chatModel: 'new-model',
          builtin: false,
        ),
        ProviderConfig(
          id: 'custom_1',
          name: 'Custom',
          type: ProviderType.openaiCompatible,
          baseUrl: 'https://c',
          apiKey: 'sk-c',
        ),
      ];

      final noSecret = mergeProviders(
        local: local,
        incoming: incoming,
        applySecrets: false,
      );
      expect(noSecret.length, 2);
      final o = noSecret.firstWhere((p) => p.id == 'openai');
      expect(o.baseUrl, 'https://new');
      expect(o.chatModel, 'new-model');
      expect(o.apiKey, 'sk-local');
      expect(o.builtin, isTrue);
      expect(noSecret.firstWhere((p) => p.id == 'custom_1').apiKey, isEmpty);

      final withSecret = mergeProviders(
        local: local,
        incoming: incoming,
        applySecrets: true,
      );
      expect(
        withSecret.firstWhere((p) => p.id == 'openai').apiKey,
        'sk-incoming',
      );
      expect(withSecret.firstWhere((p) => p.id == 'custom_1').apiKey, 'sk-c');
    },
  );

  test('clearLocalData sessions / media / all', () async {
    await seedSampleData();
    expect(imageStore.entries, isNotEmpty);
    expect(logs.totalCount, greaterThan(0));

    final mediaOnly = await service.clearLocalData(
      ClearLocalDataFlags.mediaOnly,
    );
    expect(mediaOnly.clearedMediaCache, isTrue);
    expect(mediaOnly.clearedSessions, isFalse);
    expect(imageStore.entries, isEmpty);
    expect(chatSessions.sessions.any((s) => s.title == '导出对话'), isTrue);

    await imageStore.savePng(Uint8List.fromList([9]), 'again');
    final sessionsOnly = await service.clearLocalData(
      ClearLocalDataFlags.sessionsOnly,
    );
    expect(sessionsOnly.clearedSessions, isTrue);
    expect(chatSessions.sessions.every((s) => s.messages.isEmpty), isTrue);

    await seedSampleData();
    final all = await service.clearLocalData(ClearLocalDataFlags.all);
    expect(all.clearedSessions, isTrue);
    expect(all.clearedMediaCache, isTrue);
    expect(all.clearedSettings, isTrue);
    expect(all.clearedProviders, isTrue);
    expect(all.clearedLogs, isTrue);
    expect(all.clearedSecrets, isTrue);
    expect(appearance.settings, AppearanceSettings.recommended);
    expect(logs.totalCount, 0);
    expect(providers.providers.every((p) => p.apiKey.isEmpty), isTrue);
  });

  test('estimateStorageUsage returns counts', () async {
    await seedSampleData();
    final usage = await service.estimateStorageUsage();
    expect(usage.chatSessionCount, greaterThan(0));
    expect(usage.chatMessageCount, greaterThan(0));
    expect(usage.providerCount, greaterThan(0));
    expect(usage.imageCacheBytes, greaterThan(0));
    expect(usage.totalApproxBytes, greaterThan(0));
  });

  test('export without sessions omits chat/image/video blocks', () async {
    await seedSampleData();
    final payload = await service.exportBackup(
      const DataBackupExportOptions(includeSessions: false),
    );
    expect(payload.chatSessions, isNull);
    expect(payload.imageSessions, isNull);
    expect(payload.videoSessions, isNull);
    final map = payload.toJson();
    expect(map.containsKey('chat'), isFalse);
  });

  test('export omits chat attachment local file bytes', () async {
    final chatStore = MemoryImageAssetStore();
    chatSessions = ChatSessionRepository(
      storage: MemoryChatSessionStorage(),
      attachmentStore: chatStore,
    );
    await chatSessions.load();
    service = DataBackupService(
      providers: providers,
      appearance: appearance,
      chatDefaults: chatDefaults,
      chatSessions: chatSessions,
      imageSessions: imageSessions,
      videoSessions: videoSessions,
      logs: logs,
      imageAssetStore: imageStore,
      chatAttachmentStore: chatStore,
      videoAssetStore: videoStore,
      mcpServers: mcpServers,
    );

    final chat = await chatSessions.createSession(title: '附图会话');
    final path = await chatStore.savePng(
      Uint8List.fromList([1, 2, 3, 4]),
      'chat_seed',
    );
    await chatSessions.appendMessage(
      chat.id,
      role: ChatRole.user,
      content: '看这图',
      attachments: [ImageRef(type: ImageRefType.file, src: path)],
    );

    final json = await service.exportBackupJson();
    expect(json.contains(path), isFalse);
    expect(json.contains('local-file-omitted'), isTrue);

    final media = await service.clearLocalData(ClearLocalDataFlags.mediaOnly);
    expect(media.clearedMediaCache, isTrue);
    expect(chatStore.entries, isEmpty);
  });

  test('default export omits MCP bearer token', () async {
    await seedSampleData();
    final json = await service.exportBackupJson();
    expect(json.contains('mcp-tok-backup-xyz'), isFalse);
    expect(json.contains('Biz MCP'), isTrue);
    expect(json.contains('"authToken"'), isFalse);

    final payload = DataBackupPayload.parse(json);
    expect(payload.mcpServers, isNotNull);
    expect(payload.mcpServers, isNotEmpty);
    for (final s in payload.mcpServers!) {
      expect(s.authToken, isNull);
      expect(s.config.authSecretRef, isNull);
    }
  });

  test(
    'includeSecrets exports MCP token and importSecrets restores it',
    () async {
      await seedSampleData();
      final json = await service.exportBackupJson(
        const DataBackupExportOptions(includeSecrets: true),
      );
      expect(json.contains('mcp-tok-backup-xyz'), isTrue);

      await service.clearLocalData(ClearLocalDataFlags.all);
      expect(mcpServers.servers, isEmpty);

      await service.importBackup(
        json,
        options: const DataBackupImportOptions(importSecrets: false),
      );
      expect(mcpServers.servers.any((s) => s.displayName == 'Biz MCP'), isTrue);
      final without = mcpServers.servers.firstWhere(
        (s) => s.displayName == 'Biz MCP',
      );
      expect(await mcpServers.hasBearerSecret(without.id), isFalse);

      await service.importBackup(
        json,
        options: const DataBackupImportOptions(importSecrets: true),
      );
      final withTok = mcpServers.servers.firstWhere(
        (s) => s.displayName == 'Biz MCP',
      );
      expect(
        await mcpServers.readBearerSecret(withTok.id),
        'mcp-tok-backup-xyz',
      );
    },
  );

  test('legacy backup without mcp block still imports', () async {
    final legacy = {
      'schemaVersion': dataBackupSchemaVersion,
      'exportedAtMs': 1,
      'includeSecrets': false,
      'providers': {
        'activeProviderId': '',
        'items': [
          {
            'id': 'legacy_p',
            'name': 'Legacy',
            'type': 'openai_compatible',
            'baseUrl': 'https://legacy.test/v1',
            'chatModel': 'm',
          },
        ],
      },
    };
    final result = await service.importBackup(legacy);
    expect(result.mcpImported, isFalse);
    expect(providers.providers.any((p) => p.name == 'Legacy'), isTrue);
  });

  test(
    'undeclared backup secrets are ignored even with import opt-in',
    () async {
      await seedSampleData();
      final id = mcpServers.servers.single.id;
      await mcpServers.update(
        mcpServers.findById(id)!.copyWith(env: {'TOKEN': 'local-env'}),
      );
      final backup =
          jsonDecode(await service.exportBackupJson()) as Map<String, dynamic>;
      final entries = (backup['mcp'] as Map)['servers'] as List;
      final entry = entries.single as Map;
      entry['env'] = {'TOKEN': 'injected-env'};
      entry['authToken'] = 'injected-bearer';
      entries.add({
        'id': 'injected-local',
        'displayName': 'Injected',
        'transport': 'stdio',
        'command': 'node',
        'env': {'TOKEN': 'injected-new-env'},
      });
      expect(backup['includeSecrets'], isFalse);
      final result = await service.importBackup(
        jsonEncode(backup),
        options: const DataBackupImportOptions(importSecrets: true),
      );
      expect(result.secretsApplied, isFalse);
      expect(mcpServers.findById(id)!.env, {'TOKEN': 'local-env'});
      expect(await mcpServers.readBearerSecret(id), 'mcp-tok-backup-xyz');
      expect(mcpServers.findById('injected-local')!.env, isEmpty);
      expect(mcpServers.findById('injected-local')!.canExposeTools, isFalse);
    },
  );

  test(
    'stdio backups cannot restore approval and env obeys secret options',
    () async {
      await seedSampleData();
      final id = mcpServers.servers.single.id;
      await mcpServers.update(
        mcpServers
            .findById(id)!
            .copyWith(
              transport: McpTransport.stdio,
              command: 'node',
              args: ['server.js'],
              env: {'TOKEN': 'backed-up-env'},
              enabled: true,
            ),
        stdioConfirmed: true,
      );
      final defaultJson = await service.exportBackupJson();
      expect(defaultJson, isNot(contains('backed-up-env')));
      expect(defaultJson, isNot(contains('stdioApproval')));
      await service.importBackup(defaultJson);
      expect(mcpServers.findById(id)!.env, {'TOKEN': 'backed-up-env'});
      expect(mcpServers.findById(id)!.enabled, isFalse);
      expect(mcpServers.findById(id)!.isStdioApproved, isFalse);

      final full = await service.exportBackupJson(
        const DataBackupExportOptions(includeSecrets: true),
      );
      await mcpServers.update(
        mcpServers.findById(id)!.copyWith(env: {'TOKEN': 'local-env'}),
      );
      await service.importBackup(full);
      expect(mcpServers.findById(id)!.env, {'TOKEN': 'local-env'});
      await service.importBackup(
        full,
        options: const DataBackupImportOptions(importSecrets: true),
      );
      expect(mcpServers.findById(id)!.env, {'TOKEN': 'backed-up-env'});
      expect(mcpServers.findById(id)!.isStdioApproved, isFalse);

      final forged = jsonDecode(full) as Map<String, dynamic>;
      final entry = ((forged['mcp'] as Map)['servers'] as List).single as Map;
      entry['stdioApproval'] = mcpStdioFingerprint(mcpServers.findById(id)!);
      entry['enabled'] = true;
      await service.importBackup(
        jsonEncode(forged),
        options: const DataBackupImportOptions(importSecrets: true),
      );
      expect(mcpServers.findById(id)!.canExposeTools, isFalse);
      expect(mcpServers.findById(id)!.stdioApproval, isNull);

      await service.clearLocalData(const ClearLocalDataFlags(secrets: true));
      expect(mcpServers.findById(id)!.env, isEmpty);
    },
  );

  test(
    'mobile import skips stdio and leaves existing configuration intact',
    () async {
      await seedSampleData();
      final id = mcpServers.servers.single.id;
      final backup =
          jsonDecode(await service.exportBackupJson()) as Map<String, dynamic>;
      final entry = ((backup['mcp'] as Map)['servers'] as List).single as Map;
      entry['transport'] = 'stdio';
      entry['command'] = 'node';
      final result = await service.importBackup(
        jsonEncode(backup),
        options: const DataBackupImportOptions(allowStdio: false),
      );
      expect(result.mcpServersSkipped, 1);
      expect(mcpServers.findById(id)!.transport, McpTransport.http);
    },
  );

  for (final environment in <String, Map<String, String>?>{
    'absent': null,
    'empty': {},
    'populated': {'TOKEN': 'backup-env'},
  }.entries) {
    for (final includeSecrets in [true, false]) {
      for (final importSecrets in [true, false]) {
        test(
          'prepared MCP env ${environment.key}, includeSecrets=$includeSecrets, importSecrets=$importSecrets',
          () async {
            // No bearer token: isolate env semantics from bearer-write barriers.
            final id = await mcpServers.add(
              displayName: 'Local',
              transport: McpTransport.stdio,
              command: 'node',
              env: {'TOKEN': 'local-env'},
              stdioConfirmed: true,
            );
            final raw = {
              'schemaVersion': dataBackupSchemaVersion,
              'exportedAtMs': 1,
              'includeSecrets': includeSecrets,
              'providers': {'activeProviderId': '', 'items': []},
              'mcp': {
                'servers': [
                  {
                    'id': id,
                    'displayName': 'Imported',
                    'transport': 'stdio',
                    'command': 'node',
                    'enabled': true,
                    if (environment.value != null) 'env': environment.value,
                  },
                ],
              },
            };
            final plan = await service.prepareImport(
              jsonEncode(raw),
              options: DataBackupImportOptions(importSecrets: importSecrets),
            );
            expect(
              plan.payload.mcpServers!.single.hasEnvironment,
              environment.value != null,
            );
            final result = await service.applyImport(plan);
            expect(result.mcpImported, isTrue);
            final imported = mcpServers.findById(id)!;
            expect(imported.displayName, 'Imported');
            expect(
              imported.env,
              includeSecrets && importSecrets && environment.value != null
                  ? environment.value
                  : {'TOKEN': 'local-env'},
            );
            expect(imported.enabled, isFalse);
            expect(imported.isStdioApproved, isFalse);
          },
        );
      }
    }
  }

  test(
    'absent env preserves local values; explicit empty env clears only with opt-in',
    () {
      const local = McpServerConfig(
        id: 's',
        displayName: 'Local',
        transport: McpTransport.stdio,
        command: 'node',
        env: {'TOKEN': 'local-env'},
      );
      final absent = DataBackupMcpServer.fromJson({
        'id': 's',
        'displayName': 'Absent',
        'transport': 'stdio',
        'command': 'node',
      });
      final empty = DataBackupMcpServer.fromJson({
        'id': 's',
        'displayName': 'Empty',
        'transport': 'stdio',
        'command': 'node',
        'env': {},
      });
      expect(
        mergeMcpServers(
          local: [local],
          incoming: [absent],
          applySecrets: true,
        ).servers.single.env,
        local.env,
      );
      expect(
        mergeMcpServers(
          local: [local],
          incoming: [empty],
          applySecrets: false,
        ).servers.single.env,
        local.env,
      );
      expect(
        mergeMcpServers(
          local: [local],
          incoming: [empty],
          applySecrets: true,
        ).servers.single.env,
        isEmpty,
      );
      expect(
        mergeMcpServers(
          local: [],
          incoming: [DataBackupMcpServer(config: local)],
          applySecrets: false,
        ).servers.single.env,
        isEmpty,
      );
    },
  );

  test(
    'clearLocalData secrets clears MCP tokens; all clears MCP servers',
    () async {
      await seedSampleData();
      final id = mcpServers.servers.single.id;
      expect(await mcpServers.hasBearerSecret(id), isTrue);

      final secretsOnly = await service.clearLocalData(
        const ClearLocalDataFlags(secrets: true),
      );
      expect(secretsOnly.clearedSecrets, isTrue);
      expect(mcpServers.servers, isNotEmpty);
      expect(await mcpServers.hasBearerSecret(id), isFalse);

      await mcpServers.writeBearerSecret(id, 'mcp-tok-again');
      final all = await service.clearLocalData(ClearLocalDataFlags.all);
      expect(all.clearedSecrets, isTrue);
      expect(all.clearedProviders, isTrue);
      expect(mcpServers.servers, isEmpty);
      expect(mcpSecrets.debugData, isEmpty);
    },
  );
}
