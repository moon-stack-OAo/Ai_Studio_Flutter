import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chat/chat_session_storage.dart';
import '../image/image_session_storage.dart';
import '../video/video_session_storage.dart';

import '../chat/chat_models.dart';
import '../chat/chat_session_repository.dart';
import '../image/image_asset_store.dart';
import '../image/image_models.dart';
import '../image/image_session_repository.dart';
import '../logging/app_log_repository.dart';
import '../mcp/mcp_models.dart';
import '../mcp/mcp_server_repository.dart';
import '../prompt/custom_skills.dart';
import '../provider/provider_config.dart';
import '../provider/provider_repository.dart';
import '../provider/provider_storage.dart';
import '../video/video_asset_store.dart';
import '../video/video_models.dart';
import '../video/video_poster_store.dart';
import '../video/video_session_repository.dart';
import 'appearance_repository.dart';
import 'asset_reference_guard.dart';
import 'chat_defaults_repository.dart';
import 'data_backup.dart';
import 'history_snapshot_store.dart';

/// SET-DATA：设置导入导出与本地数据清理。
///
/// 调用约定：
/// - 若有进行中的对话 / 生图 / 生视频任务，**UI 应先停止**再调用
///   [importBackup] / [clearLocalData]；本服务幂等，但不取消网络请求。
/// - 破坏性操作（清数据、导入含密钥）须由 UI 二次确认。
/// - MCP：默认导出 omit Bearer；清密钥 / 清全部时清 MCP secret；清提供商时清 Server 列表。
class DataBackupService {
  DataBackupService({
    required ProviderRepository providers,
    required AppearanceRepository appearance,
    required ChatDefaultsRepository chatDefaults,
    required ChatSessionRepository chatSessions,
    required ImageSessionRepository imageSessions,
    required VideoSessionRepository videoSessions,
    AppLogRepository? logs,
    ImageAssetStore? imageAssetStore,
    ImageAssetStore? chatAttachmentStore,
    VideoAssetStore? videoAssetStore,
    this._videoPosterStore,
    McpServerRepository? mcpServers,
    SkillRepository? skillRepository,
  }) : _providers = providers,
       _appearance = appearance,
       _chatDefaults = chatDefaults,
       _chatSessions = chatSessions,
       _imageSessions = imageSessions,
       _videoSessions = videoSessions,
       _logs = logs,
       _imageAssetStore = imageAssetStore ?? imageSessions.assetStore,
       _chatAttachmentStore =
           chatAttachmentStore ?? chatSessions.attachmentStore,
       _videoAssetStore = videoAssetStore ?? videoSessions.assetStore,
       _mcpServers = mcpServers,
       _skillRepository = skillRepository;

  final ProviderRepository _providers;
  final AppearanceRepository _appearance;
  final ChatDefaultsRepository _chatDefaults;
  final ChatSessionRepository _chatSessions;
  final ImageSessionRepository _imageSessions;
  final VideoSessionRepository _videoSessions;
  final AppLogRepository? _logs;
  final ImageAssetStore _imageAssetStore;
  final ImageAssetStore _chatAttachmentStore;
  final VideoAssetStore _videoAssetStore;
  final VideoPosterStore? _videoPosterStore;
  final McpServerRepository? _mcpServers;
  final SkillRepository? _skillRepository;

  static const _journalKey = 'core.backup_import_progress.v1';
  bool _importing = false;
  bool _clearing = false;
  void _checkPendingSecrets() {
    if (_providers.hasPendingSecretWrites || (_mcpServers?.hasPendingSecretWrites ?? false)) {
      throw StateError('安全存储仍在处理中，请稍后重新预览');
    }
  }
  final Expando<String> _preparedInputs = Expando<String>();
  String importRecoverySummary = '';

  Future<void> loadImportStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(const Duration(seconds: 3));
      final raw = prefs.getString(_journalKey);
      importRecoverySummary = raw == null ? '' :
          '上次导入未确认全部完成，可能部分成功。请重新选择备份并预览；不会自动重放或回滚。';
    } catch (_) {
      importRecoverySummary = '导入进度暂时不可读取，请检查本机存储；不会自动重放。';
    }
  }

  Future<void> _journal(List<String> completed, String stage) async {
    final prefs = await SharedPreferences.getInstance();
    final value = jsonEncode({'schema': 1, 'completed': completed, 'stage': stage});
    final saved = await prefs.setString(_journalKey, value);
    await prefs.reload();
    if (!saved) throw StateError('导入进度保存失败');
    if (prefs.getString(_journalKey) != value) throw StateError('导入进度校验失败');
    importRecoverySummary = '导入尚未全部完成，可能部分成功；不会自动重放或回滚。';
  }

  Future<void> _clearImportStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final removed = !prefs.containsKey(_journalKey) || await prefs.remove(_journalKey);
    await prefs.reload();
    if (!removed || prefs.containsKey(_journalKey)) {
      throw StateError('导入进度清理失败');
    }
    importRecoverySummary = '';
  }

  String _baseline() => sha256.convert(utf8.encode(jsonEncode({
    'providers': [for (final p in _providers.providers) p.toJson()],
    'active': _providers.activeProviderId,
    'appearance': _appearance.settings.toJson(),
    'defaults': _chatDefaults.defaults.toJson(),
    'chat': [for (final s in _chatSessions.sessions) s.toJson()],
    'chatActive': _chatSessions.activeId,
    'image': [for (final s in _imageSessions.sessions) s.toJson()],
    'imageActive': _imageSessions.activeId,
    'video': [for (final s in _videoSessions.sessions) s.toJson()],
    'videoActive': _videoSessions.activeId,
    'mcp': [for (final s in _mcpServers?.servers ?? <McpServerConfig>[]) {...s.toJsonMeta(), 'environment': s.env, 'credentialRevision': _mcpServers?.secretRevision(s.id)}],
    'skills': [for (final s in _skillRepository?.skills ?? <CustomSkill>[]) s.toJson()],
  }))).toString();

  Future<DataBackupImportPlan> prepareImport(Object raw, {
    DataBackupImportOptions options = const DataBackupImportOptions(),
  }) async {
    if (_clearing || _importing) throw StateError('数据操作进行中');
    _checkPendingSecrets();
    final payload = DataBackupPayload.parse(raw);
    await _ensureLoaded();
    await _providers.waitForPersist();
    await _mcpServers?.waitForPersist();
    await _appearance.waitForPersist();
    await _chatDefaults.waitForPersist();
    await _skillRepository?.waitForPersist();
    _checkPendingSecrets();
    if (_clearing || _importing || !_providers.isLoaded || _providers.lastError != null ||
        !_appearance.isLoaded || _appearance.lastError != null ||
        !_chatDefaults.isLoaded || _chatDefaults.lastError != null ||
        (_mcpServers != null && (!_mcpServers.isLoaded || _mcpServers.lastError != null))) {
      throw DataBackupFormatException('本机设置尚未可靠读取，请恢复存储后重试');
    }
    if (options.importSessions && options.replaceSessions &&
        ((payload.chatSessions != null && _chatSessions.writesBlocked) ||
         (payload.imageSessions != null && _imageSessions.writesBlocked) ||
         (payload.videoSessions != null && _videoSessions.writesBlocked))) {
      throw DataBackupFormatException('选中历史不可写，请先恢复历史');
    }
    if (options.importSkills && payload.skills != null && _skillRepository != null &&
        (!_skillRepository.isLoaded || _skillRepository.lastError != null)) {
      throw DataBackupFormatException('本机技能尚未可靠读取，请先恢复或明确清除后重试');
    }
    final counts = <String>[];
    final localIds = _providers.providers.map((p) => p.id).toSet();
    counts.add('提供商：新增 ${payload.providers.where((p) => !localIds.contains(p.id)).length}，更新 ${payload.providers.where((p) => localIds.contains(p.id)).length}');
    if (payload.appearance != null) counts.add('替换外观');
    if (options.importChatDefaults && payload.chatDefaults != null) counts.add('替换对话默认');
    if (options.importSessions && options.replaceSessions) {
      if (payload.chatSessions != null) {
        final prepared = prepareChatPersistPayload(ChatStoreSnapshot(sessions: payload.chatSessions!, activeId: payload.chatActiveId ?? ''));
        final beforeMessages = payload.chatSessions!.expand((s) => s.messages).length;
        final afterMessages = prepared.sessions.expand((s) => s.messages).length;
        final keptIds = prepared.sessions.map((s) => s.id).toSet();
        final truncated = payload.chatSessions!.where((s) => keptIds.contains(s.id)).expand((s) => s.messages.skip(s.messages.length > maxChatMessagesPerSession ? s.messages.length - maxChatMessagesPerSession : 0)).where((m) => m.content.length > maxChatMessageChars).length;
        counts.add('替换对话：${prepared.sessions.length} 个会话（原备份 ${payload.chatSessions!.length}）；消息 $afterMessages/$beforeMessages，内容截断 $truncated 条（每会话最多 $maxChatMessagesPerSession 条，每条 $maxChatMessageChars 字符）');
      }
      if (payload.imageSessions != null) {
        final prepared = prepareImagePersistPayload(ImageStoreSnapshot(sessions: payload.imageSessions!, activeId: payload.imageActiveId ?? ''));
        counts.add('替换生图：${prepared.sessions.length} 个会话（原备份 ${payload.imageSessions!.length}）；记录 ${prepared.sessions.expand((s) => s.items).length}/${payload.imageSessions!.expand((s) => s.items).length}');
      }
      if (payload.videoSessions != null) {
        final prepared = prepareVideoPersistPayload(VideoStoreSnapshot(sessions: payload.videoSessions!, activeId: payload.videoActiveId ?? ''));
        counts.add('替换视频：${prepared.sessions.length} 个会话（原备份 ${payload.videoSessions!.length}）；记录 ${prepared.sessions.expand((s) => s.items).length}/${payload.videoSessions!.expand((s) => s.items).length}');
      }
    }
    if (options.importMcpServers && payload.mcpServers != null) {
      final skipped = payload.mcpServers!.where((s) => !options.allowStdio && s.config.transport == McpTransport.stdio).length;
      counts.add(_mcpServers == null ? '跳过 MCP：当前无可用仓库' : '合并 MCP：${payload.mcpServers!.length - skipped} 项；跳过本地进程 $skipped 项');
    }
    if (options.importSkills && payload.skills != null) counts.add(_skillRepository == null ? '跳过技能：当前无可用仓库' : '合并技能：${payload.skills!.length} 项');
    counts.add(options.importSecrets && payload.includeSecrets ? '将应用备份密钥；本地进程仍须重新确认' : '不导入密钥');
    counts.add('仅元数据，不含媒体二进制；历史按现有容量限制保留。空历史按现有规则创建空会话。导入可能部分成功，不支持全局回滚。');
    final plan = DataBackupImportPlan(payload: payload, options: options, baseline: _baseline(), summary: counts.join(String.fromCharCode(10)));
    _preparedInputs[plan] = payload.encodeJson(pretty: false);
    return plan;
  }

  /// Shared repositories are exposed only as recovery actions/status, not UI.
  List<HistoryRecoveryState> get historyRecoveryStates => [
    _chatSessions.recoveryState,
    _imageSessions.recoveryState,
    _videoSessions.recoveryState,
  ];

  Future<void> recoverHistory() async {
    if (_chatSessions.writesBlocked) await _chatSessions.recoverHistory();
    if (_imageSessions.writesBlocked) await _imageSessions.recoverHistory();
    if (_videoSessions.writesBlocked) await _videoSessions.recoverHistory();
  }

  String get historyRecoverySummary {
    final states = historyRecoveryStates;
    if (states.contains(HistoryRecoveryState.damaged) ||
        states.contains(HistoryRecoveryState.readFailed)) {
      return '历史数据读取异常，已阻止覆盖原数据。可重试恢复；无有效恢复点时请先保留本机数据。';
    }
    if (states.contains(HistoryRecoveryState.recovered)) {
      return '已从有效快照恢复历史，损坏原数据已隔离保留。';
    }
    return '历史数据正常；保留上一有效快照用于异常恢复。';
  }

  /// 导出备份为 [DataBackupPayload]（再 [DataBackupPayload.encodeJson]）。
  Future<DataBackupPayload> exportBackup([
    DataBackupExportOptions options = const DataBackupExportOptions(),
  ]) async {
    await _ensureLoaded();

    List<ChatSession>? chat;
    String? chatActive;
    List<ImageSession>? image;
    String? imageActive;
    List<VideoSession>? video;
    String? videoActive;

    if (options.includeSessions) {
      chat = List<ChatSession>.from(_chatSessions.sessions);
      chatActive = _chatSessions.activeId;
      image = List<ImageSession>.from(_imageSessions.sessions);
      imageActive = _imageSessions.activeId;
      video = List<VideoSession>.from(_videoSessions.sessions);
      videoActive = _videoSessions.activeId;
    }

    List<DataBackupMcpServer>? mcp;
    final mcpRepo = _mcpServers;
    if (options.includeMcpServers && mcpRepo != null) {
      mcp = <DataBackupMcpServer>[];
      for (final s in mcpRepo.servers) {
        String? token;
        if (options.includeSecrets && s.authKind == McpAuthKind.bearer) {
          token = await mcpRepo.readBearerSecret(s.id);
        }
        mcp.add(DataBackupMcpServer(config: s, authToken: token));
      }
    }

    return DataBackupPayload(
      schemaVersion: dataBackupSchemaVersion,
      exportedAtMs: DateTime.now().millisecondsSinceEpoch,
      includeSecrets: options.includeSecrets,
      appearance: _appearance.settings,
      chatDefaults: options.includeChatDefaults ? _chatDefaults.defaults : null,
      providers: List<ProviderConfig>.from(_providers.providers),
      activeProviderId: _providers.activeProviderId,
      chatSessions: chat,
      chatActiveId: chatActive,
      imageSessions: image,
      imageActiveId: imageActive,
      videoSessions: video,
      videoActiveId: videoActive,
      mcpServers: mcp,
      skills: options.includeSkills ? _skillRepository?.skills : null,
    );
  }

  /// 导出 JSON 字符串。
  Future<String> exportBackupJson([
    DataBackupExportOptions options = const DataBackupExportOptions(),
    bool pretty = true,
  ]) async {
    final payload = await exportBackup(options);
    return payload.encodeJson(pretty: pretty);
  }

  /// 导入备份。格式错误抛 [DataBackupFormatException]；
  /// 版本不兼容抛 [DataBackupSchemaException]。
  Future<DataBackupImportResult> importBackup(
    Object raw, {
    DataBackupImportOptions options = const DataBackupImportOptions(),
  }) async {
    final plan = await prepareImport(raw, options: options);
    return applyImport(plan);
  }

  Future<DataBackupImportResult> applyImport(DataBackupImportPlan plan) async {
    if (_clearing || _importing) throw StateError('数据操作进行中');
    _checkPendingSecrets();
    await _providers.waitForPersist();
    await _mcpServers?.waitForPersist();
    await _appearance.waitForPersist();
    await _chatDefaults.waitForPersist();
    await _skillRepository?.waitForPersist();
    _checkPendingSecrets();
    final prepared = _preparedInputs[plan];
    if (_clearing || _importing || prepared == null || _providers.lastError != null ||
        _mcpServers?.lastError != null || _appearance.lastError != null ||
        _chatDefaults.lastError != null ||
        (plan.options.importSkills && plan.payload.skills != null && _skillRepository?.lastError != null) ||
        plan.baseline != _baseline()) {
      throw DataBackupFormatException('本机数据已变更，请重新预览并确认');
    }
    final payload = DataBackupPayload.parse(prepared);
    _preparedInputs[plan] = null;
    final options = plan.options;
    final oldChat = List<ChatSession>.from(_chatSessions.sessions);
    final oldImage = List<ImageSession>.from(_imageSessions.sessions);
    final oldVideo = List<VideoSession>.from(_videoSessions.sessions);
    final applyPlannedSecrets = options.importSecrets && payload.includeSecrets;
    final plannedMcp = options.importMcpServers && _mcpServers != null && payload.mcpServers != null
        ? mergeMcpServers(local: _mcpServers.servers, incoming: payload.mcpServers!.where((e) => options.allowStdio || e.config.transport != McpTransport.stdio).toList(), applySecrets: applyPlannedSecrets)
        : null;
    final planned = <String>[
      '提供商', if (payload.appearance != null) '外观',
      if (options.importChatDefaults && payload.chatDefaults != null) '对话默认',
      if (options.importSessions && options.replaceSessions) ...[
        if (payload.chatSessions != null) '对话历史',
        if (payload.imageSessions != null) '生图历史',
        if (payload.videoSessions != null) '视频历史',
      ],
      if (plannedMcp != null) ...[
        'MCP 配置', for (var i = 1; i <= plannedMcp.secretsToWrite.length; i++) 'MCP 密钥 $i/${plannedMcp.secretsToWrite.length}',
      ],
      if (options.importSkills && _skillRepository != null && payload.skills != null) '技能',
    ];
    _importing = true;
    final completed = <String>[];
    final attempted = <String>{};
    var businessWritesComplete = false;
    var stage = '准备';
    Future<void> step(String name, Future<void> Function() action) async {
      stage = '进度记录（下一项：$name，尚未开始该项写入）';
      await _journal(completed, name);
      stage = '$name 写入结果未知，需核对';
      attempted.add(name);
      await action();
      completed.add(name);
      stage = '进度记录（$name 已完成）';
      await _journal(completed, '待继续');
    }
    try {
    final applySecrets = options.importSecrets && payload.includeSecrets;

    final localProviders = List<ProviderConfig>.from(_providers.providers);
    final localIds = {for (final p in localProviders) p.id};
    final merged = mergeProviders(
      local: localProviders,
      incoming: payload.providers,
      applySecrets: applySecrets,
    );
    var added = 0;
    var updated = 0;
    for (final p in payload.providers) {
      if (localIds.contains(p.id)) {
        updated++;
      } else {
        added++;
      }
    }

    var activeId = payload.activeProviderId.trim();
    if (activeId.isEmpty || !merged.any((p) => p.id == activeId)) {
      activeId = _providers.activeProviderId;
      if (!merged.any((p) => p.id == activeId) && merged.isNotEmpty) {
        activeId = merged.first.id;
      }
    }

    await step('提供商', () => _providers.replaceAll(
      ProviderStoreSnapshot(providers: merged, activeProviderId: activeId),
    ));

    var appearanceImported = false;
    if (payload.appearance != null) {
      await step('外观', () => _appearance.save(payload.appearance!));
      appearanceImported = true;
    }

    var chatDefaultsImported = false;
    if (options.importChatDefaults && payload.chatDefaults != null) {
      await step('对话默认', () => _chatDefaults.save(payload.chatDefaults!));
      chatDefaultsImported = true;
    }

    var sessionsImported = false;
    if (options.importSessions && options.replaceSessions) {
      if (payload.chatSessions != null) {
        await step('对话历史', () => _chatSessions.replaceAll(
          prepareChatPersistPayload(ChatStoreSnapshot(
            sessions: payload.chatSessions!,
            activeId: payload.chatActiveId ?? '',
          )), deleteAssets: false,
        ));
        sessionsImported = true;
      }
      if (payload.imageSessions != null) {
        await step('生图历史', () => _imageSessions.replaceAll(
          prepareImagePersistPayload(ImageStoreSnapshot(
            sessions: payload.imageSessions!,
            activeId: payload.imageActiveId ?? '',
          )), deleteAssets: false,
        ));
        sessionsImported = true;
      }
      if (payload.videoSessions != null) {
        await step('视频历史', () => _videoSessions.replaceAll(
          prepareVideoPersistPayload(VideoStoreSnapshot(
            sessions: payload.videoSessions!,
            activeId: payload.videoActiveId ?? '',
          )), deleteAssets: false,
        ));
        sessionsImported = true;
      }
    }

    var mcpImported = false;
    var mcpMerged = 0;
    var mcpAdded = 0;
    var mcpSkipped = 0;
    final mcpRepo = _mcpServers;
    final incomingMcp = payload.mcpServers;
    if (options.importMcpServers && mcpRepo != null && incomingMcp != null) {
      final accepted = incomingMcp
          .where(
            (entry) =>
                options.allowStdio ||
                entry.config.transport != McpTransport.stdio,
          )
          .toList();
      mcpSkipped = incomingMcp.length - accepted.length;
      final merge = mergeMcpServers(
        local: List<McpServerConfig>.from(mcpRepo.servers),
        incoming: accepted,
        applySecrets: applySecrets,
      );
      await step('MCP 配置', () => mcpRepo.replaceAll(merge.servers,
        importedIds: accepted.map((s) => s.config.id).toSet()));
      var secretIndex = 0;
      for (final e in merge.secretsToWrite.entries) {
        secretIndex++;
        await step('MCP 密钥 $secretIndex/${merge.secretsToWrite.length}', () async {
          await mcpRepo.writeBearerSecret(e.key, e.value);
          // Bearer writes enqueue an optimistic metadata/environment save. Wait
          // for our own queue before the strict save, without bypassing the
          // guarded store's pending barrier (including timed-out platform IO).
          await mcpRepo.waitForPersist();
          if (mcpRepo.lastError != null) {
            throw StateError('MCP 密钥配置保存未完成');
          }
          if (await mcpRepo.readBearerSecret(e.key) != e.value) {
            throw StateError('MCP 密钥安全存储回读失败');
          }
          await mcpRepo.replaceAll(mcpRepo.servers, importedIds: const {});
        });
      }
      mcpMerged = merge.mergedCount;
      mcpAdded = merge.addedCount;
      mcpImported = true;
    }

    var skillsImported = false;
    var skillsMerged = 0;
    var skillsAdded = 0;
    final skillRepo = _skillRepository;
    final incomingSkills = payload.skills;
    if (options.importSkills && skillRepo != null && incomingSkills != null) {
      final localIds = skillRepo.skills.map((s) => s.id).toSet();
      skillsMerged = incomingSkills
          .where((s) => localIds.contains(s.id))
          .length;
      skillsAdded = incomingSkills.length - skillsMerged;
      await step('技能', () => skillRepo.merge(incomingSkills));
      skillsImported = true;
    }

    businessWritesComplete = true;
    stage = '进度清理（所有业务写入已完成）';
    await _clearImportStatus();
    // Metadata has committed everywhere. Cleanup is best effort, never rollback.
    if (options.importSessions && options.replaceSessions) {
      try {
        if (payload.chatSessions != null) await _chatSessions.cleanupReplacedAssets(oldChat);
        if (payload.imageSessions != null) await _imageSessions.cleanupReplacedAssets(oldImage);
        if (payload.videoSessions != null) await _videoSessions.cleanupReplacedAssets(oldVideo);
      } catch (_) {
        importRecoverySummary = '导入已完成，部分旧媒体清理未完成。';
      }
    }
    return DataBackupImportResult(
      schemaVersion: payload.schemaVersion,
      providersMerged: updated,
      providersAdded: added,
      secretsApplied: applySecrets,
      sessionsImported: sessionsImported,
      appearanceImported: appearanceImported,
      chatDefaultsImported: chatDefaultsImported,
      mcpServersMerged: mcpMerged,
      mcpServersAdded: mcpAdded,
      mcpImported: mcpImported,
      mcpServersSkipped: mcpSkipped,
      skillsImported: skillsImported,
      skillsMerged: skillsMerged,
      skillsAdded: skillsAdded,
    );
    } catch (_) {
      throw DataBackupImportFailure(completed: List.unmodifiable(completed), failedStage: stage,
        notAttempted: List.unmodifiable(planned.where((s) => !attempted.contains(s))),
        businessWritesComplete: businessWritesComplete);
    } finally {
      _importing = false;
    }
  }

  /// 清除本地数据。幂等。
  ///
  /// 注意：不会停止进行中的生成任务；调用前 UI 应先取消。
  Future<ClearLocalDataResult> clearLocalData([
    ClearLocalDataFlags flags = ClearLocalDataFlags.all,
  ]) async {
    if (_importing || _clearing) throw StateError('数据操作进行中，请稍后清除');
    _checkPendingSecrets();
    _clearing = true;
    try {
    if (flags.isNoop) {
      return const ClearLocalDataResult(
        clearedSessions: false,
        clearedMediaCache: false,
        clearedSettings: false,
        clearedProviders: false,
        clearedLogs: false,
        clearedSecrets: false,
      );
    }

    await _ensureLoaded();

    var clearedSessions = false;
    var clearedMedia = false;
    var clearedSettings = false;
    var clearedProviders = false;
    var clearedLogs = false;
    var clearedSecrets = false;

    if (flags.sessions) {
      final chatRefs = _chatSessions.sessions
          .expand((s) => s.messages)
          .expand((m) => m.attachments)
          .where((r) => r.type == ImageRefType.file)
          .map((r) => r.src)
          .toSet();
      final imageRefs = _imageSessions.sessions
          .expand((s) => s.items)
          .expand((i) => [...i.images, ...i.referenceImages])
          .where((r) => r.type == ImageRefType.file)
          .map((r) => r.src)
          .toSet();
      final videoItems = _videoSessions.sessions
          .expand((s) => s.items)
          .toList();
      // Do not delete any assets until every history clear has committed.
      // This is intentionally not a transaction: an earlier history may be empty
      // when a later clear fails, but no media is lost on that failure.
      await _chatSessions.clearAllSessions(deleteAssets: false);
      await _imageSessions.clearAllSessions(deleteAssets: false);
      await _videoSessions.clearAllSessions(deleteAssets: false);
      clearedSessions = true;
      if (!flags.mediaCache) {
        final retained = <String>{
          ..._chatSessions.sessions
              .expand((s) => s.messages)
              .expand((m) => m.attachments)
              .where((r) => r.type == ImageRefType.file)
              .map((r) => assetReferenceKey(r.src)),
          ..._imageSessions.sessions
              .expand((s) => s.items)
              .expand((i) => [...i.images, ...i.referenceImages])
              .where((r) => r.type == ImageRefType.file)
              .map((r) => assetReferenceKey(r.src)),
          ..._videoSessions.sessions
              .expand((s) => s.items)
              .expand(
                (i) => [
                  if (i.localPath != null) i.localPath!,
                  if (i.videoUrl != null) i.videoUrl!,
                  if (i.posterLocalPath != null) i.posterLocalPath!,
                  ...i.referenceImages
                      .where((r) => r.type == ImageRefType.file)
                      .map((r) => r.src),
                ],
              )
              .map(assetReferenceKey),
        };
        for (final path in chatRefs) {
          if (retained.contains(assetReferenceKey(path))) continue;
          try {
            await _chatAttachmentStore.delete(path);
          } catch (_) {}
        }
        for (final path in imageRefs) {
          if (retained.contains(assetReferenceKey(path))) continue;
          try {
            await _imageAssetStore.delete(path);
          } catch (_) {}
        }
        for (final item in videoItems) {
          final path = item.localPath ?? item.videoUrl;
          if (path != null &&
              !retained.contains(assetReferenceKey(path)) &&
              !path.startsWith('http') &&
              !path.startsWith('data:')) {
            try {
              await _videoAssetStore.delete(path);
            } catch (_) {}
          }
          final poster = item.posterLocalPath;
          if (poster != null && !retained.contains(assetReferenceKey(poster))) {
            try {
              await _videoPosterStore?.delete(item.id);
            } catch (_) {}
          }
          for (final ref in item.referenceImages.where(
            (r) => r.type == ImageRefType.file,
          )) {
            if (retained.contains(assetReferenceKey(ref.src))) continue;
            try {
              await _videoSessions.referenceImageStore.delete(ref.src);
            } catch (_) {}
          }
        }
      }
    }
    if (flags.mediaCache) {
      try {
        await _imageAssetStore.clearAll();
      } catch (_) {}
      try {
        await _chatAttachmentStore.clearAll();
      } catch (_) {}
      try {
        await _videoAssetStore.clearAll();
      } catch (_) {}
      try {
        await _videoPosterStore?.clearAll();
      } catch (_) {}
      clearedMedia = true;
    }

    if (flags.settings) {
      await _appearance.resetToRecommended();
      await _chatDefaults.resetToRecommended();
      await _skillRepository?.clear();
      clearedSettings = true;
    }

    if (flags.providers) {
      await _providers.resetPresets();
      clearedProviders = true;
      // resetPresets 会清空自定义项；密钥随快照重写
      if (flags.secrets) clearedSecrets = true;
      // 清提供商配置时一并清空 MCP Server 列表（含 secret）
      final mcpRepo = _mcpServers;
      if (mcpRepo != null) {
        await mcpRepo.clearAllServers();
        if (flags.secrets) clearedSecrets = true;
      }
    } else if (flags.secrets) {
      final wiped = [
        for (final p in _providers.providers) p.copyWith(apiKey: ''),
      ];
      await _providers.replaceAll(
        ProviderStoreSnapshot(
          providers: wiped,
          activeProviderId: _providers.activeProviderId,
        ),
      );
      final mcpRepo = _mcpServers;
      if (mcpRepo != null) {
        await mcpRepo.clearAllSecrets();
      }
      clearedSecrets = true;
    }

    if (flags.logs) {
      final logs = _logs;
      if (logs != null) {
        await logs.clear();
        clearedLogs = true;
      }
    }

    if (flags.sessions) await _clearImportStatus();
    return ClearLocalDataResult(
      clearedSessions: clearedSessions,
      clearedMediaCache: clearedMedia,
      clearedSettings: clearedSettings,
      clearedProviders: clearedProviders,
      clearedLogs: clearedLogs,
      clearedSecrets: clearedSecrets,
    );
    } finally {
      _clearing = false;
    }
  }

  /// 估算本地占用，供 UI 展示。
  Future<StorageUsageEstimate> estimateStorageUsage() async {
    await _ensureLoaded();

    var chatMessages = 0;
    for (final s in _chatSessions.sessions) {
      chatMessages += s.messages.length;
    }

    var approxJson = 0;
    try {
      approxJson += utf8
          .encode(jsonEncode(_appearance.settings.toJson()))
          .length;
      approxJson += utf8
          .encode(jsonEncode(_chatDefaults.defaults.toJson()))
          .length;
      final skillRepo = _skillRepository;
      if (skillRepo != null) {
        approxJson += utf8
            .encode(
              jsonEncode(skillRepo.skills.map((s) => s.toJson()).toList()),
            )
            .length;
      }
      approxJson += utf8
          .encode(
            jsonEncode({
              'providers': _providers.providers
                  .map((p) => p.toJsonMeta())
                  .toList(),
            }),
          )
          .length;
      approxJson += utf8
          .encode(
            jsonEncode({
              'sessions': _chatSessions.sessions
                  .map((s) => s.toJson())
                  .toList(),
            }),
          )
          .length;
      approxJson += utf8
          .encode(
            jsonEncode({
              'sessions': _imageSessions.sessions
                  .map((s) => s.toJson())
                  .toList(),
            }),
          )
          .length;
      approxJson += utf8
          .encode(
            jsonEncode({
              'sessions': _videoSessions.sessions
                  .map((s) => s.toJson())
                  .toList(),
            }),
          )
          .length;
    } catch (_) {}

    final imageBytes = await _safeEstimate(_imageAssetStore.estimateBytes);
    final chatAttBytes = await _safeEstimate(
      _chatAttachmentStore.estimateBytes,
    );
    final videoBytes = await _safeEstimate(_videoAssetStore.estimateBytes);
    final posterStore = _videoPosterStore;
    final posterBytes = posterStore == null
        ? 0
        : await _safeEstimate(posterStore.estimateBytes);

    return StorageUsageEstimate(
      chatSessionCount: _chatSessions.sessions.length,
      imageSessionCount: _imageSessions.sessions.length,
      videoSessionCount: _videoSessions.sessions.length,
      chatMessageCount: chatMessages,
      providerCount: _providers.providers.length,
      logEntryCount: _logs?.totalCount ?? 0,
      imageCacheBytes: imageBytes + chatAttBytes,
      videoCacheBytes: videoBytes + posterBytes,
      approxJsonBytes: approxJson,
      skillCount: _skillRepository?.skills.length ?? 0,
    );
  }

  Future<void> _ensureLoaded() async {
    if (!_providers.isLoaded) await _providers.load();
    if (!_appearance.isLoaded) await _appearance.load();
    if (!_chatDefaults.isLoaded) await _chatDefaults.load();
    if (!_chatSessions.isLoaded) await _chatSessions.load();
    if (!_imageSessions.isLoaded) await _imageSessions.load();
    if (!_videoSessions.isLoaded) await _videoSessions.load();
    final skillRepo = _skillRepository;
    if (skillRepo != null && !skillRepo.isLoaded) await skillRepo.load();
    final mcp = _mcpServers;
    if (mcp != null && !mcp.isLoaded) await mcp.load();
    final logs = _logs;
    if (logs != null && !logs.isLoaded) await logs.load();
  }

  Future<int> _safeEstimate(Future<int> Function() fn) async {
    try {
      return await fn();
    } catch (_) {
      return 0;
    }
  }
}
