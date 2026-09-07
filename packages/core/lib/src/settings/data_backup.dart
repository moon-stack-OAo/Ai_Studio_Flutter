import 'dart:convert';

import '../chat/chat_models.dart';
import '../image/image_models.dart';
import '../provider/provider_config.dart';
import '../video/video_models.dart';
import 'appearance_settings.dart';
import 'chat_defaults.dart';

/// 当前备份 JSON schema 版本。不兼容升级时递增并在导入处拒绝旧版。
const int dataBackupSchemaVersion = 1;

/// 导出选项。
class DataBackupExportOptions {
  const DataBackupExportOptions({
    this.includeSecrets = false,
    this.includeSessions = true,
    this.includeChatDefaults = true,
  });

  /// 是否导出 API Key 明文。默认 false；true 时见 SECURITY.md 风险说明。
  final bool includeSecrets;

  /// 是否导出对话 / 生图 / 生视频会话（不含媒体二进制）。
  final bool includeSessions;

  /// 是否导出对话全局默认。
  final bool includeChatDefaults;
}

/// 导入选项。
class DataBackupImportOptions {
  const DataBackupImportOptions({
    this.importSecrets = false,
    this.importSessions = true,
    this.importChatDefaults = true,
    this.replaceSessions = true,
  });

  /// 是否接受备份中的 API Key。仅当导出时含密钥且本项为 true 时覆盖本地密钥。
  final bool importSecrets;

  /// 是否导入会话。
  final bool importSessions;

  /// 是否导入对话默认。
  final bool importChatDefaults;

  /// true：用备份会话整体替换本地；false：仅合并提供商/设置（会话跳过）。
  final bool replaceSessions;
}

/// 清数据档位 / 开关。
class ClearLocalDataFlags {
  const ClearLocalDataFlags({
    this.sessions = false,
    this.mediaCache = false,
    this.settings = false,
    this.providers = false,
    this.logs = false,
    this.secrets = false,
  });

  /// 清除全部（含密钥）。调用方 UI 必须二次确认。
  static const ClearLocalDataFlags all = ClearLocalDataFlags(
    sessions: true,
    mediaCache: true,
    settings: true,
    providers: true,
    logs: true,
    secrets: true,
  );

  /// 仅会话（对话 / 生图 / 生视频元数据）；媒体缓存另开 [mediaCache]。
  static const ClearLocalDataFlags sessionsOnly = ClearLocalDataFlags(
    sessions: true,
  );

  /// 仅媒体二进制缓存。
  static const ClearLocalDataFlags mediaOnly = ClearLocalDataFlags(
    mediaCache: true,
  );

  final bool sessions;
  final bool mediaCache;
  final bool settings;
  final bool providers;
  final bool logs;

  /// 清除提供商 API Key。与 [providers] 独立：可只清密钥保留元数据。
  final bool secrets;

  bool get isNoop =>
      !sessions &&
      !mediaCache &&
      !settings &&
      !providers &&
      !logs &&
      !secrets;
}

/// 本地占用估算（供 UI 展示）。
class StorageUsageEstimate {
  const StorageUsageEstimate({
    required this.chatSessionCount,
    required this.imageSessionCount,
    required this.videoSessionCount,
    required this.chatMessageCount,
    required this.providerCount,
    required this.logEntryCount,
    required this.imageCacheBytes,
    required this.videoCacheBytes,
    required this.approxJsonBytes,
  });

  final int chatSessionCount;
  final int imageSessionCount;
  final int videoSessionCount;
  final int chatMessageCount;
  final int providerCount;
  final int logEntryCount;
  final int imageCacheBytes;
  final int videoCacheBytes;

  /// 会话/设置 JSON 大致字节（UTF-8 编码长度估算）。
  final int approxJsonBytes;

  int get mediaCacheBytes => imageCacheBytes + videoCacheBytes;

  int get totalApproxBytes => approxJsonBytes + mediaCacheBytes;
}

/// 导入结果摘要。
class DataBackupImportResult {
  const DataBackupImportResult({
    required this.schemaVersion,
    required this.providersMerged,
    required this.providersAdded,
    required this.secretsApplied,
    required this.sessionsImported,
    required this.appearanceImported,
    required this.chatDefaultsImported,
  });

  final int schemaVersion;
  final int providersMerged;
  final int providersAdded;
  final bool secretsApplied;
  final bool sessionsImported;
  final bool appearanceImported;
  final bool chatDefaultsImported;
}

/// 清数据结果摘要。
class ClearLocalDataResult {
  const ClearLocalDataResult({
    required this.clearedSessions,
    required this.clearedMediaCache,
    required this.clearedSettings,
    required this.clearedProviders,
    required this.clearedLogs,
    required this.clearedSecrets,
  });

  final bool clearedSessions;
  final bool clearedMediaCache;
  final bool clearedSettings;
  final bool clearedProviders;
  final bool clearedLogs;
  final bool clearedSecrets;
}

/// 备份 / 导入格式错误。
class DataBackupFormatException implements Exception {
  DataBackupFormatException(this.message);

  final String message;

  @override
  String toString() => 'DataBackupFormatException: $message';
}

/// 备份 schema 不兼容。
class DataBackupSchemaException implements Exception {
  DataBackupSchemaException(this.message, {this.foundVersion});

  final String message;
  final int? foundVersion;

  @override
  String toString() => 'DataBackupSchemaException: $message';
}

/// 解析后的备份载荷（内存结构）。
class DataBackupPayload {
  const DataBackupPayload({
    required this.schemaVersion,
    required this.exportedAtMs,
    required this.includeSecrets,
    required this.appearance,
    required this.chatDefaults,
    required this.providers,
    required this.activeProviderId,
    required this.chatSessions,
    required this.chatActiveId,
    required this.imageSessions,
    required this.imageActiveId,
    required this.videoSessions,
    required this.videoActiveId,
  });

  final int schemaVersion;
  final int exportedAtMs;
  final bool includeSecrets;
  final AppearanceSettings? appearance;
  final ChatDefaults? chatDefaults;
  final List<ProviderConfig> providers;
  final String activeProviderId;
  final List<ChatSession>? chatSessions;
  final String? chatActiveId;
  final List<ImageSession>? imageSessions;
  final String? imageActiveId;
  final List<VideoSession>? videoSessions;
  final String? videoActiveId;

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'exportedAtMs': exportedAtMs,
      'includeSecrets': includeSecrets,
      if (appearance != null) 'appearance': appearance!.toJson(),
      if (chatDefaults != null) 'chatDefaults': chatDefaults!.toJson(),
      'providers': {
        'activeProviderId': activeProviderId,
        'items': [
          for (final p in providers)
            includeSecrets ? p.toJson() : p.toJsonMeta(),
        ],
      },
    };
    if (chatSessions != null) {
      map['chat'] = {
        'activeId': chatActiveId ?? '',
        'sessions': chatSessions!.map((s) => s.toJson()).toList(),
      };
    }
    if (imageSessions != null) {
      map['image'] = {
        'activeId': imageActiveId ?? '',
        'sessions': [
          for (final s in imageSessions!) _imageSessionMetaJson(s),
        ],
      };
    }
    if (videoSessions != null) {
      map['video'] = {
        'activeId': videoActiveId ?? '',
        'sessions': [
          for (final s in videoSessions!) _videoSessionMetaJson(s),
        ],
      };
    }
    return map;
  }

  String encodeJson({bool pretty = true}) {
    if (pretty) {
      return const JsonEncoder.withIndent('  ').convert(toJson());
    }
    return jsonEncode(toJson());
  }

  /// 从 JSON map / 字符串解析；格式错误抛 [DataBackupFormatException]。
  static DataBackupPayload parse(Object raw) {
    Map<String, dynamic> map;
    try {
      if (raw is String) {
        final trimmed = raw.trim();
        if (trimmed.isEmpty) {
          throw DataBackupFormatException('备份内容为空');
        }
        if (trimmed.length > maxBackupJsonChars) {
          throw DataBackupFormatException(
            '备份过大（超过 ${maxBackupJsonChars ~/ (1024 * 1024)}MB）',
          );
        }
        final decoded = jsonDecode(trimmed);
        if (decoded is! Map) {
          throw DataBackupFormatException('根节点必须是 JSON 对象');
        }
        map = Map<String, dynamic>.from(decoded);
      } else if (raw is Map) {
        map = Map<String, dynamic>.from(raw);
      } else {
        throw DataBackupFormatException('不支持的备份输入类型');
      }
    } on DataBackupFormatException {
      rethrow;
    } on FormatException catch (e) {
      throw DataBackupFormatException('JSON 解析失败：${e.message}');
    } catch (e) {
      throw DataBackupFormatException('无法读取备份：$e');
    }

    final versionRaw = map['schemaVersion'];
    final version = versionRaw is int
        ? versionRaw
        : (versionRaw is num
            ? versionRaw.toInt()
            : int.tryParse(versionRaw?.toString() ?? ''));
    if (version == null) {
      throw DataBackupFormatException('缺少 schemaVersion');
    }
    if (version != dataBackupSchemaVersion) {
      throw DataBackupSchemaException(
        '不支持的备份版本 $version（当前支持 $dataBackupSchemaVersion）',
        foundVersion: version,
      );
    }

    AppearanceSettings? appearance;
    final appearanceRaw = map['appearance'];
    if (appearanceRaw is Map) {
      appearance = AppearanceSettings.fromJson(
        Map<String, dynamic>.from(appearanceRaw),
      );
    }

    ChatDefaults? chatDefaults;
    final defaultsRaw = map['chatDefaults'];
    if (defaultsRaw is Map) {
      chatDefaults = ChatDefaults.fromJson(
        Map<String, dynamic>.from(defaultsRaw),
      );
    }

    final providersBlock = map['providers'];
    if (providersBlock is! Map) {
      throw DataBackupFormatException('缺少 providers 对象');
    }
    final providersMap = Map<String, dynamic>.from(providersBlock);
    final itemsRaw = providersMap['items'];
    if (itemsRaw is! List) {
      throw DataBackupFormatException('providers.items 必须是数组');
    }
    final providers = <ProviderConfig>[];
    for (final entry in itemsRaw) {
      if (entry is! Map) continue;
      final item = Map<String, dynamic>.from(entry);
      final id = item['id']?.toString().trim() ?? '';
      if (id.isEmpty) continue;
      providers.add(ProviderConfig.fromJson(item));
    }
    final activeProviderId =
        providersMap['activeProviderId']?.toString().trim() ?? '';

    List<ChatSession>? chatSessions;
    String? chatActiveId;
    final chatRaw = map['chat'];
    if (chatRaw is Map) {
      final chatMap = Map<String, dynamic>.from(chatRaw);
      chatActiveId = chatMap['activeId']?.toString() ?? '';
      chatSessions = _parseChatSessions(chatMap['sessions']);
    }

    List<ImageSession>? imageSessions;
    String? imageActiveId;
    final imageRaw = map['image'];
    if (imageRaw is Map) {
      final imageMap = Map<String, dynamic>.from(imageRaw);
      imageActiveId = imageMap['activeId']?.toString() ?? '';
      imageSessions = _parseImageSessions(imageMap['sessions']);
    }

    List<VideoSession>? videoSessions;
    String? videoActiveId;
    final videoRaw = map['video'];
    if (videoRaw is Map) {
      final videoMap = Map<String, dynamic>.from(videoRaw);
      videoActiveId = videoMap['activeId']?.toString() ?? '';
      videoSessions = _parseVideoSessions(videoMap['sessions']);
    }

    final exportedAt = map['exportedAtMs'];
    final exportedAtMs = exportedAt is int
        ? exportedAt
        : (exportedAt is num
            ? exportedAt.toInt()
            : DateTime.now().millisecondsSinceEpoch);

    return DataBackupPayload(
      schemaVersion: version,
      exportedAtMs: exportedAtMs,
      includeSecrets: map['includeSecrets'] == true,
      appearance: appearance,
      chatDefaults: chatDefaults,
      providers: providers,
      activeProviderId: activeProviderId,
      chatSessions: chatSessions,
      chatActiveId: chatActiveId,
      imageSessions: imageSessions,
      imageActiveId: imageActiveId,
      videoSessions: videoSessions,
      videoActiveId: videoActiveId,
    );
  }
}

/// 备份 JSON 字符上限（防过大输入拖垮解析）。
const int maxBackupJsonChars = 32 * 1024 * 1024;

List<ChatSession> _parseChatSessions(Object? raw) {
  if (raw is! List) return const [];
  final out = <ChatSession>[];
  for (final e in raw) {
    if (e is Map) {
      out.add(ChatSession.fromJson(Map<String, dynamic>.from(e)));
    }
  }
  return out;
}

List<ImageSession> _parseImageSessions(Object? raw) {
  if (raw is! List) return const [];
  final out = <ImageSession>[];
  for (final e in raw) {
    if (e is Map) {
      out.add(ImageSession.fromJson(Map<String, dynamic>.from(e)));
    }
  }
  return out;
}

List<VideoSession> _parseVideoSessions(Object? raw) {
  if (raw is! List) return const [];
  final out = <VideoSession>[];
  for (final e in raw) {
    if (e is Map) {
      out.add(VideoSession.fromJson(Map<String, dynamic>.from(e)));
    }
  }
  return out;
}

/// 生图会话导出：去掉本地 file / 过大 b64，仅保留引用元数据。
Map<String, dynamic> _imageSessionMetaJson(ImageSession session) {
  final items = <Map<String, dynamic>>[];
  for (final item in session.items) {
    final images = <Map<String, dynamic>>[];
    for (final img in item.images) {
      switch (img.type) {
        case ImageRefType.file:
          images.add({
            'type': ImageRefType.file.wire,
            'src': '',
            'note': 'local-file-omitted',
            if (img.revisedPrompt != null && img.revisedPrompt!.isNotEmpty)
              'revisedPrompt': img.revisedPrompt,
          });
        case ImageRefType.b64:
          // 不把二进制塞进备份
          images.add({
            'type': ImageRefType.url.wire,
            'src': '',
            'note': 'b64-omitted',
            if (img.revisedPrompt != null && img.revisedPrompt!.isNotEmpty)
              'revisedPrompt': img.revisedPrompt,
          });
        case ImageRefType.url:
          images.add(img.toJson());
      }
    }
    final map = item.toJson();
    map['images'] = images;
    // 截断可能含 dataURL 的预览
    final ref = map['refPreview']?.toString();
    if (ref != null && (ref.startsWith('data:') || ref.length > 256)) {
      map.remove('refPreview');
    }
    items.add(map);
  }
  return {
    'id': session.id,
    'title': session.title,
    'createdAt': session.createdAt,
    'updatedAt': session.updatedAt,
    'items': items,
  };
}

Map<String, dynamic> _videoSessionMetaJson(VideoSession session) {
  final items = <Map<String, dynamic>>[];
  for (final item in session.items) {
    final map = Map<String, dynamic>.from(item.toJson());
    // 本地路径不跨机；清空以免导入后指向错误文件
    map.remove('localPath');
    final url = map['videoUrl']?.toString();
    if (url != null &&
        (url.startsWith('file:') ||
            url.startsWith('memory://') ||
            (!url.startsWith('http') && url.isNotEmpty))) {
      map.remove('videoUrl');
    }
    final ref = map['refPreview']?.toString();
    if (ref != null && (ref.startsWith('data:') || ref.length > 256)) {
      map.remove('refPreview');
    }
    items.add(map);
  }
  return {
    'id': session.id,
    'title': session.title,
    'createdAt': session.createdAt,
    'updatedAt': session.updatedAt,
    'items': items,
  };
}

/// 按 id 合并提供商：同 id 覆盖非密钥字段；密钥仅在 [applySecrets] 且源有值时覆盖。
List<ProviderConfig> mergeProviders({
  required List<ProviderConfig> local,
  required List<ProviderConfig> incoming,
  required bool applySecrets,
}) {
  final byId = <String, ProviderConfig>{
    for (final p in local) p.id: p,
  };
  for (final src in incoming) {
    final existing = byId[src.id];
    if (existing == null) {
      byId[src.id] = applySecrets
          ? src
          : src.copyWith(apiKey: '');
      continue;
    }
    final nextKey = applySecrets && src.apiKey.trim().isNotEmpty
        ? src.apiKey
        : existing.apiKey;
    byId[src.id] = existing.copyWith(
      name: src.name,
      type: src.type,
      baseUrl: src.baseUrl,
      apiKey: nextKey,
      chatModel: src.chatModel,
      imageModel: src.imageModel,
      videoModel: src.videoModel,
      enabled: src.enabled,
      // 内置标记以本地为准，避免导入抹掉
      builtin: existing.builtin,
      lastTestOk: src.lastTestOk,
      lastTestDetail: src.lastTestDetail,
      lastTestAtMs: src.lastTestAtMs,
    );
  }
  // 保持本地顺序，新增的追加到末尾
  final result = <ProviderConfig>[];
  final seen = <String>{};
  for (final p in local) {
    final merged = byId[p.id];
    if (merged != null) {
      result.add(merged);
      seen.add(p.id);
    }
  }
  for (final p in incoming) {
    if (seen.contains(p.id)) continue;
    final merged = byId[p.id];
    if (merged != null) {
      result.add(merged);
      seen.add(p.id);
    }
  }
  return result;
}
