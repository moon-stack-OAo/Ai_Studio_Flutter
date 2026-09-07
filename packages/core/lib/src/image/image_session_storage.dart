import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'image_models.dart';

/// 最多保留会话数。
const int maxImageSessions = 20;

/// 单会话最多条目数。
const int maxImageItemsPerSession = 50;

/// refPreview 字符上限（避免 dataURL 撑爆）。
const int maxImageRefPreviewChars = 256;

/// 单条 b64 src 字符上限（落盘前兜底；优先用 ImageAssetStore）。
const int maxImageB64SrcChars = 120000;

ImageItem sanitizeImageItem(ImageItem item) {
  var next = item;
  final ref = next.refPreview;
  if (ref != null && ref.length > maxImageRefPreviewChars) {
    next = next.copyWith(clearRefPreview: true);
  }
  final imgs = <ImageRef>[];
  for (final img in next.images) {
    if (img.type == ImageRefType.b64 &&
        img.src.length > maxImageB64SrcChars) {
      // 过大 b64 丢弃，避免 prefs 爆仓；应由 assetStore 落盘为 file。
      continue;
    }
    imgs.add(img);
  }
  if (imgs.length != next.images.length) {
    next = next.copyWith(images: imgs);
  }
  return next;
}

ImageSession sanitizeImageSession(
  ImageSession session, {
  int maxItems = maxImageItemsPerSession,
}) {
  final limit = maxItems < 1 ? 1 : maxItems;
  var items = List<ImageItem>.from(session.items);
  if (items.length > limit) {
    items = items.sublist(items.length - limit);
  }
  items = items.map(sanitizeImageItem).toList();
  return session.copyWith(items: items);
}

List<ImageSession> capImageSessionCount(
  List<ImageSession> sessions,
  String? activeId, {
  int maxSessions = maxImageSessions,
}) {
  final limit = maxSessions < 1 ? 1 : maxSessions;
  if (sessions.length <= limit) return List<ImageSession>.from(sessions);

  final sorted = List<ImageSession>.from(sessions)
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

/// hydrate：残留 loading → error「上次异常中断」。
List<ImageSession> clearStaleImageLoading(List<ImageSession> sessions) {
  return sessions.map((session) {
    final items = session.items.map((item) {
      if (item.status != ImageItemStatus.loading) return item;
      return item.copyWith(
        status: ImageItemStatus.error,
        errorMessage:
            (item.errorMessage == null || item.errorMessage!.isEmpty)
                ? '上次异常中断'
                : item.errorMessage,
      );
    }).toList();
    return session.copyWith(items: items);
  }).toList();
}

ImageStoreSnapshot prepareImagePersistPayload(
  ImageStoreSnapshot snapshot, {
  int maxSessions = maxImageSessions,
  int maxItemsPerSession = maxImageItemsPerSession,
}) {
  var sessions = snapshot.sessions
      .map((s) => sanitizeImageSession(s, maxItems: maxItemsPerSession))
      .toList();
  sessions = capImageSessionCount(
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
  return ImageStoreSnapshot(sessions: sessions, activeId: activeId);
}

abstract class ImageSessionStorage {
  Future<ImageStoreSnapshot> load();

  Future<void> save(ImageStoreSnapshot snapshot);
}

/// SharedPreferences：`core.image_sessions.v1` → `{sessions, activeId}`。
class PrefsImageSessionStorage implements ImageSessionStorage {
  PrefsImageSessionStorage({SharedPreferences? prefs}) : _prefsOverride = prefs;

  static const prefsKey = 'core.image_sessions.v1';

  final SharedPreferences? _prefsOverride;
  SharedPreferences? _prefs;

  Future<SharedPreferences> _ensurePrefs() async {
    return _prefs ??= _prefsOverride ?? await SharedPreferences.getInstance();
  }

  @override
  Future<ImageStoreSnapshot> load() async {
    final prefs = await _ensurePrefs();
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) {
      return const ImageStoreSnapshot(sessions: [], activeId: '');
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const ImageStoreSnapshot(sessions: [], activeId: '');
      }
      final listRaw = decoded['sessions'];
      final sessions = <ImageSession>[];
      if (listRaw is List) {
        for (final e in listRaw) {
          if (e is Map) {
            sessions.add(ImageSession.fromJson(Map<String, dynamic>.from(e)));
          }
        }
      }
      final prepared = prepareImagePersistPayload(
        ImageStoreSnapshot(
          sessions: clearStaleImageLoading(sessions),
          activeId: decoded['activeId']?.toString() ?? '',
        ),
      );
      return prepared;
    } catch (_) {
      return const ImageStoreSnapshot(sessions: [], activeId: '');
    }
  }

  @override
  Future<void> save(ImageStoreSnapshot snapshot) async {
    final prefs = await _ensurePrefs();
    final prepared = prepareImagePersistPayload(snapshot);
    final payload = <String, dynamic>{
      'activeId': prepared.activeId,
      'sessions': prepared.sessions.map((s) => s.toJson()).toList(),
    };
    await prefs.setString(prefsKey, jsonEncode(payload));
  }
}

/// 内存存储（单元测试）。
class MemoryImageSessionStorage implements ImageSessionStorage {
  MemoryImageSessionStorage([ImageStoreSnapshot? initial])
      : _snapshot = initial ??
            const ImageStoreSnapshot(sessions: [], activeId: '');

  ImageStoreSnapshot _snapshot;

  @override
  Future<ImageStoreSnapshot> load() async {
    final cleared = clearStaleImageLoading(_snapshot.sessions);
    final prepared = prepareImagePersistPayload(
      ImageStoreSnapshot(sessions: cleared, activeId: _snapshot.activeId),
    );
    return ImageStoreSnapshot(
      sessions: List<ImageSession>.from(prepared.sessions),
      activeId: prepared.activeId,
    );
  }

  @override
  Future<void> save(ImageStoreSnapshot snapshot) async {
    final prepared = prepareImagePersistPayload(snapshot);
    _snapshot = ImageStoreSnapshot(
      sessions: List<ImageSession>.from(prepared.sessions),
      activeId: prepared.activeId,
    );
  }
}
