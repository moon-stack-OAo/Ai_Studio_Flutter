import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'video_models.dart';

/// 最多保留会话数。
const int maxVideoSessions = 20;

/// 单会话最多条目数。
const int maxVideoItemsPerSession = 50;

/// refPreview 字符上限。
const int maxVideoRefPreviewChars = 256;

VideoItem sanitizeVideoItem(VideoItem item) {
  var next = item;
  final ref = next.refPreview;
  if (ref != null && ref.length > maxVideoRefPreviewChars) {
    next = next.copyWith(clearRefPreview: true);
  }
  // 禁止持久化巨大 dataURL
  final url = next.videoUrl;
  if (url != null && url.startsWith('data:') && url.length > 2048) {
    next = next.copyWith(
      clearVideoUrl: true,
      errorMessage: (next.errorMessage == null || next.errorMessage!.isEmpty)
          ? '视频过大未缓存，请重新生成'
          : next.errorMessage,
    );
  }
  // 仅保留 https remote
  final remote = next.remoteVideoUrl?.trim();
  if (remote != null &&
      remote.isNotEmpty &&
      !RegExp(r'^https?://', caseSensitive: false).hasMatch(remote)) {
    next = next.copyWith(clearRemoteVideoUrl: true);
  }
  return next;
}

VideoSession sanitizeVideoSession(
  VideoSession session, {
  int maxItems = maxVideoItemsPerSession,
}) {
  final limit = maxItems < 1 ? 1 : maxItems;
  var items = List<VideoItem>.from(session.items);
  if (items.length > limit) {
    items = items.sublist(items.length - limit);
  }
  items = items.map(sanitizeVideoItem).toList();
  return session.copyWith(items: items);
}

List<VideoSession> capVideoSessionCount(
  List<VideoSession> sessions,
  String? activeId, {
  int maxSessions = maxVideoSessions,
}) {
  final limit = maxSessions < 1 ? 1 : maxSessions;
  if (sessions.length <= limit) return List<VideoSession>.from(sessions);

  final sorted = List<VideoSession>.from(sessions)
    ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
  final keep = <String>{};
  if (activeId != null && sorted.any((s) => s.id == activeId)) {
    keep.add(activeId);
  }
  for (var i = sorted.length - 1; i >= 0 && keep.length < limit; i--) {
    keep.add(sorted[i].id);
  }
  return sessions.where((s) => keep.contains(s.id)).toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
}

/// hydrate：loading+jobId → pending_resume；loading 无 jobId → error。
List<VideoSession> hydrateVideoLoading(List<VideoSession> sessions) {
  return sessions.map((session) {
    final items = session.items.map((item) {
      if (item.status != VideoItemStatus.loading) return item;
      final jid = item.jobId?.trim() ?? '';
      if (jid.isNotEmpty) {
        return item.copyWith(
          status: VideoItemStatus.pendingResume,
          needsResume: true,
        );
      }
      return item.copyWith(
        status: VideoItemStatus.error,
        needsResume: false,
        errorMessage:
            (item.errorMessage == null || item.errorMessage!.isEmpty)
                ? '上次异常中断'
                : item.errorMessage,
      );
    }).toList();
    return session.copyWith(items: items);
  }).toList();
}

/// hydrate：失效的非 file 本地引用回退 remote https。
List<VideoSession> hydrateVideoUrls(List<VideoSession> sessions) {
  return sessions.map((session) {
    final items = session.items.map((item) {
      final url = item.videoUrl;
      if (url == null) return item;
      // memory:// 仅测试；真实 hydrate 时若有 remote 则回退
      if (url.startsWith('memory://')) {
        final remote = item.remoteVideoUrl;
        if (remote != null &&
            RegExp(r'^https?://', caseSensitive: false).hasMatch(remote)) {
          return item.copyWith(videoUrl: remote);
        }
      }
      return item;
    }).toList();
    return session.copyWith(items: items);
  }).toList();
}

VideoStoreSnapshot prepareVideoPersistPayload(
  VideoStoreSnapshot snapshot, {
  int maxSessions = maxVideoSessions,
  int maxItemsPerSession = maxVideoItemsPerSession,
}) {
  var sessions = snapshot.sessions
      .map((s) => sanitizeVideoSession(s, maxItems: maxItemsPerSession))
      .toList();
  sessions = capVideoSessionCount(
    sessions,
    snapshot.activeId,
    maxSessions: maxSessions,
  );
  var activeId = snapshot.activeId;
  if (sessions.isEmpty) {
    activeId = '';
  } else if (!sessions.any((s) => s.id == activeId)) {
    activeId = sessions.first.id;
  }
  return VideoStoreSnapshot(sessions: sessions, activeId: activeId);
}

abstract class VideoSessionStorage {
  Future<VideoStoreSnapshot> load();

  Future<void> save(VideoStoreSnapshot snapshot);
}

/// SharedPreferences：`core.video_sessions.v1` → `{sessions, activeId}`。
class PrefsVideoSessionStorage implements VideoSessionStorage {
  PrefsVideoSessionStorage({SharedPreferences? prefs}) : _prefsOverride = prefs;

  static const prefsKey = 'core.video_sessions.v1';

  final SharedPreferences? _prefsOverride;
  SharedPreferences? _prefs;

  Future<SharedPreferences> _ensurePrefs() async {
    return _prefs ??= _prefsOverride ?? await SharedPreferences.getInstance();
  }

  @override
  Future<VideoStoreSnapshot> load() async {
    final prefs = await _ensurePrefs();
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) {
      return const VideoStoreSnapshot(sessions: [], activeId: '');
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const VideoStoreSnapshot(sessions: [], activeId: '');
      }
      final listRaw = decoded['sessions'];
      final sessions = <VideoSession>[];
      if (listRaw is List) {
        for (final e in listRaw) {
          if (e is Map) {
            sessions.add(VideoSession.fromJson(Map<String, dynamic>.from(e)));
          }
        }
      }
      final hydrated = hydrateVideoUrls(hydrateVideoLoading(sessions));
      return prepareVideoPersistPayload(
        VideoStoreSnapshot(
          sessions: hydrated,
          activeId: decoded['activeId']?.toString() ?? '',
        ),
      );
    } catch (_) {
      return const VideoStoreSnapshot(sessions: [], activeId: '');
    }
  }

  @override
  Future<void> save(VideoStoreSnapshot snapshot) async {
    final prefs = await _ensurePrefs();
    final prepared = prepareVideoPersistPayload(snapshot);
    final payload = <String, dynamic>{
      'activeId': prepared.activeId,
      'sessions': prepared.sessions.map((s) => s.toJson()).toList(),
    };
    await prefs.setString(prefsKey, jsonEncode(payload));
  }
}

/// 内存存储（单元测试）。
class MemoryVideoSessionStorage implements VideoSessionStorage {
  MemoryVideoSessionStorage([VideoStoreSnapshot? initial])
      : _snapshot = initial ??
            const VideoStoreSnapshot(sessions: [], activeId: '');

  VideoStoreSnapshot _snapshot;

  @override
  Future<VideoStoreSnapshot> load() async {
    final hydrated =
        hydrateVideoUrls(hydrateVideoLoading(_snapshot.sessions));
    final prepared = prepareVideoPersistPayload(
      VideoStoreSnapshot(sessions: hydrated, activeId: _snapshot.activeId),
    );
    return VideoStoreSnapshot(
      sessions: List<VideoSession>.from(prepared.sessions),
      activeId: prepared.activeId,
    );
  }

  @override
  Future<void> save(VideoStoreSnapshot snapshot) async {
    final prepared = prepareVideoPersistPayload(snapshot);
    _snapshot = VideoStoreSnapshot(
      sessions: List<VideoSession>.from(prepared.sessions),
      activeId: prepared.activeId,
    );
  }
}
