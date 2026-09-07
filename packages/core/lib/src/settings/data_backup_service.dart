import 'dart:convert';

import '../chat/chat_models.dart';
import '../chat/chat_session_repository.dart';
import '../image/image_asset_store.dart';
import '../image/image_models.dart';
import '../image/image_session_repository.dart';
import '../logging/app_log_repository.dart';
import '../provider/provider_config.dart';
import '../provider/provider_repository.dart';
import '../provider/provider_storage.dart';
import '../video/video_asset_store.dart';
import '../video/video_models.dart';
import '../video/video_session_repository.dart';
import 'appearance_repository.dart';
import 'chat_defaults_repository.dart';
import 'data_backup.dart';

/// SET-DATA：设置导入导出与本地数据清理。
///
/// 调用约定：
/// - 若有进行中的对话 / 生图 / 生视频任务，**UI 应先停止**再调用
///   [importBackup] / [clearLocalData]；本服务幂等，但不取消网络请求。
/// - 破坏性操作（清数据、导入含密钥）须由 UI 二次确认。
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
    VideoAssetStore? videoAssetStore,
  })  : _providers = providers,
        _appearance = appearance,
        _chatDefaults = chatDefaults,
        _chatSessions = chatSessions,
        _imageSessions = imageSessions,
        _videoSessions = videoSessions,
        _logs = logs,
        _imageAssetStore = imageAssetStore ?? imageSessions.assetStore,
        _videoAssetStore = videoAssetStore ?? videoSessions.assetStore;

  final ProviderRepository _providers;
  final AppearanceRepository _appearance;
  final ChatDefaultsRepository _chatDefaults;
  final ChatSessionRepository _chatSessions;
  final ImageSessionRepository _imageSessions;
  final VideoSessionRepository _videoSessions;
  final AppLogRepository? _logs;
  final ImageAssetStore _imageAssetStore;
  final VideoAssetStore _videoAssetStore;

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

    return DataBackupPayload(
      schemaVersion: dataBackupSchemaVersion,
      exportedAtMs: DateTime.now().millisecondsSinceEpoch,
      includeSecrets: options.includeSecrets,
      appearance: _appearance.settings,
      chatDefaults:
          options.includeChatDefaults ? _chatDefaults.defaults : null,
      providers: List<ProviderConfig>.from(_providers.providers),
      activeProviderId: _providers.activeProviderId,
      chatSessions: chat,
      chatActiveId: chatActive,
      imageSessions: image,
      imageActiveId: imageActive,
      videoSessions: video,
      videoActiveId: videoActive,
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
    final payload = DataBackupPayload.parse(raw);
    await _ensureLoaded();

    final applySecrets =
        options.importSecrets && payload.includeSecrets;

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

    await _providers.replaceAll(
      ProviderStoreSnapshot(providers: merged, activeProviderId: activeId),
    );

    var appearanceImported = false;
    if (payload.appearance != null) {
      await _appearance.save(payload.appearance!);
      appearanceImported = true;
    }

    var chatDefaultsImported = false;
    if (options.importChatDefaults && payload.chatDefaults != null) {
      await _chatDefaults.save(payload.chatDefaults!);
      chatDefaultsImported = true;
    }

    var sessionsImported = false;
    if (options.importSessions && options.replaceSessions) {
      if (payload.chatSessions != null) {
        await _chatSessions.replaceAll(
          ChatStoreSnapshot(
            sessions: payload.chatSessions!,
            activeId: payload.chatActiveId ?? '',
          ),
        );
        sessionsImported = true;
      }
      if (payload.imageSessions != null) {
        await _imageSessions.replaceAll(
          ImageStoreSnapshot(
            sessions: payload.imageSessions!,
            activeId: payload.imageActiveId ?? '',
          ),
        );
        sessionsImported = true;
      }
      if (payload.videoSessions != null) {
        await _videoSessions.replaceAll(
          VideoStoreSnapshot(
            sessions: payload.videoSessions!,
            activeId: payload.videoActiveId ?? '',
          ),
        );
        sessionsImported = true;
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
    );
  }

  /// 清除本地数据。幂等。
  ///
  /// 注意：不会停止进行中的生成任务；调用前 UI 应先取消。
  Future<ClearLocalDataResult> clearLocalData([
    ClearLocalDataFlags flags = ClearLocalDataFlags.all,
  ]) async {
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
      await _chatSessions.clearAllSessions();
      await _imageSessions.clearAllSessions(
        clearMediaCache: flags.mediaCache,
      );
      await _videoSessions.clearAllSessions(
        clearMediaCache: flags.mediaCache,
      );
      clearedSessions = true;
      if (flags.mediaCache) clearedMedia = true;
    } else if (flags.mediaCache) {
      try {
        await _imageAssetStore.clearAll();
      } catch (_) {}
      try {
        await _videoAssetStore.clearAll();
      } catch (_) {}
      clearedMedia = true;
    }

    if (flags.settings) {
      await _appearance.resetToRecommended();
      await _chatDefaults.resetToRecommended();
      clearedSettings = true;
    }

    if (flags.providers) {
      await _providers.resetPresets();
      clearedProviders = true;
      // resetPresets 会清空自定义项；密钥随快照重写
      if (flags.secrets) clearedSecrets = true;
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
      clearedSecrets = true;
    }

    if (flags.logs) {
      final logs = _logs;
      if (logs != null) {
        await logs.clear();
        clearedLogs = true;
      }
    }

    return ClearLocalDataResult(
      clearedSessions: clearedSessions,
      clearedMediaCache: clearedMedia,
      clearedSettings: clearedSettings,
      clearedProviders: clearedProviders,
      clearedLogs: clearedLogs,
      clearedSecrets: clearedSecrets,
    );
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
      approxJson += utf8
          .encode(
            jsonEncode({
              'providers':
                  _providers.providers.map((p) => p.toJsonMeta()).toList(),
            }),
          )
          .length;
      approxJson += utf8
          .encode(
            jsonEncode({
              'sessions':
                  _chatSessions.sessions.map((s) => s.toJson()).toList(),
            }),
          )
          .length;
      approxJson += utf8
          .encode(
            jsonEncode({
              'sessions':
                  _imageSessions.sessions.map((s) => s.toJson()).toList(),
            }),
          )
          .length;
      approxJson += utf8
          .encode(
            jsonEncode({
              'sessions':
                  _videoSessions.sessions.map((s) => s.toJson()).toList(),
            }),
          )
          .length;
    } catch (_) {}

    final imageBytes = await _safeEstimate(_imageAssetStore.estimateBytes);
    final videoBytes = await _safeEstimate(_videoAssetStore.estimateBytes);

    return StorageUsageEstimate(
      chatSessionCount: _chatSessions.sessions.length,
      imageSessionCount: _imageSessions.sessions.length,
      videoSessionCount: _videoSessions.sessions.length,
      chatMessageCount: chatMessages,
      providerCount: _providers.providers.length,
      logEntryCount: _logs?.totalCount ?? 0,
      imageCacheBytes: imageBytes,
      videoCacheBytes: videoBytes,
      approxJsonBytes: approxJson,
    );
  }

  Future<void> _ensureLoaded() async {
    if (!_providers.isLoaded) await _providers.load();
    if (!_appearance.isLoaded) await _appearance.load();
    if (!_chatDefaults.isLoaded) await _chatDefaults.load();
    if (!_chatSessions.isLoaded) await _chatSessions.load();
    if (!_imageSessions.isLoaded) await _imageSessions.load();
    if (!_videoSessions.isLoaded) await _videoSessions.load();
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
