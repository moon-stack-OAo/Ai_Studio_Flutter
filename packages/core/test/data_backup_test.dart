import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

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
  late DataBackupService service;

  setUp(() async {
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

    await providers.load();
    await appearance.load();
    await chatDefaults.load();
    await chatSessions.load();
    await imageSessions.load();
    await videoSessions.load();
    await logs.load();

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
    );
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
    await imageSessions.completeItem(
      img.id,
      imgItem.id,
      [ImageRef(type: ImageRefType.file, src: path)],
    );

    await logs.append(
      level: AppLogLevel.info,
      source: 'test',
      message: 'seed',
    );
  }

  test('export → import roundtrip preserves appearance / providers / chat',
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
    expect(
      providers.providers.any((p) => p.name == 'BackupMe'),
      isTrue,
    );
    final restored = providers.providers.firstWhere((p) => p.name == 'BackupMe');
    expect(restored.apiKey, isEmpty); // 默认不含密钥
    expect(restored.baseUrl, 'https://api.backup.test/v1');
    expect(restored.chatModel, 'gpt-test');
    expect(
      chatSessions.sessions.any((s) => s.title == '导出对话'),
      isTrue,
    );
  });

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

  test('mergeProviders: same id overwrites meta; secrets only when allowed',
      () {
    final local = [
      const ProviderConfig(
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
      const ProviderConfig(
        id: 'openai',
        name: 'OpenAI Cloud',
        type: ProviderType.openai,
        baseUrl: 'https://new',
        apiKey: 'sk-incoming',
        chatModel: 'new-model',
        builtin: false,
      ),
      const ProviderConfig(
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
    expect(
      withSecret.firstWhere((p) => p.id == 'custom_1').apiKey,
      'sk-c',
    );
  });

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
    expect(
      chatSessions.sessions.any((s) => s.title == '导出对话'),
      isTrue,
    );

    await imageStore.savePng(Uint8List.fromList([9]), 'again');
    final sessionsOnly = await service.clearLocalData(
      ClearLocalDataFlags.sessionsOnly,
    );
    expect(sessionsOnly.clearedSessions, isTrue);
    expect(
      chatSessions.sessions.every((s) => s.messages.isEmpty),
      isTrue,
    );

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
}
