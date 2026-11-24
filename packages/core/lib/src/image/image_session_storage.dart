import 'dart:io';

import '../settings/file_history_snapshot_store.dart';
import 'dart:convert';

import '../settings/history_snapshot_store.dart';

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

List<ImageRef> _sanitizeImageRefList(List<ImageRef> list) {
  final out = <ImageRef>[];
  for (final img in list) {
    if (img.type == ImageRefType.b64 && img.src.length > maxImageB64SrcChars) {
      // 过大 b64 丢弃，避免 prefs 爆仓；应由 assetStore 落盘为 file。
      continue;
    }
    out.add(img);
  }
  return out;
}

ImageItem sanitizeImageItem(ImageItem item) {
  var next = item;
  final ref = next.refPreview;
  if (ref != null && ref.length > maxImageRefPreviewChars) {
    next = next.copyWith(clearRefPreview: true);
  }
  final imgs = _sanitizeImageRefList(next.images);
  if (imgs.length != next.images.length) {
    next = next.copyWith(images: imgs);
  }
  var refs = _sanitizeImageRefList(next.referenceImages);
  if (refs.length > maxTurnReferenceImages) {
    refs = refs.sublist(0, maxTurnReferenceImages);
  }
  if (refs.length != next.referenceImages.length) {
    next = next.copyWith(referenceImages: refs);
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
        errorMessage: (item.errorMessage == null || item.errorMessage!.isEmpty)
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
class PrefsImageSessionStorage
    implements
        ImageSessionStorage,
        RecoverableHistoryStorage<ImageStoreSnapshot> {
  PrefsImageSessionStorage({SharedPreferences? prefs}) : _prefsOverride = prefs;

  static const prefsKey = 'core.image_sessions.v1';

  final SharedPreferences? _prefsOverride;
  SharedPreferences? _prefs;

  late final HistorySnapshotStore<ImageStoreSnapshot> _history =
      HistorySnapshotStore(
        key: prefsKey,
        prefs: _ensurePrefs,
        decode: _decode,
        empty: const ImageStoreSnapshot(sessions: [], activeId: ''),
      );

  @override
  HistoryRecoveryState get recoveryState => _history.state;
  @override
  bool get writesBlocked => _history.blocked;
  @override
  Future<ImageStoreSnapshot> recover() => _history.recover();
  @override
  Future<void> replaceHistory(ImageStoreSnapshot snapshot) async {
    final prepared = prepareImagePersistPayload(snapshot);
    await _history.replace(
      jsonEncode({
        'activeId': prepared.activeId,
        'sessions': prepared.sessions.map((s) => s.toJson()).toList(),
      }),
    );
  }

  @override
  Future<void> clearHistory(ImageStoreSnapshot empty) async {
    await _history.clear();
    await save(empty);
  }

  Future<SharedPreferences> _ensurePrefs() async {
    return _prefs ??= _prefsOverride ?? await SharedPreferences.getInstance();
  }

  @override
  Future<ImageStoreSnapshot> load() => _history.load();

  static ImageStoreSnapshot _decode(String raw) {
    final decoded = decodeHistoryObject(raw, 'items');
    return prepareImagePersistPayload(
      ImageStoreSnapshot(
        sessions: clearStaleImageLoading(
          (decoded['sessions'] as List)
              .map(
                (e) =>
                    ImageSession.fromJson(Map<String, dynamic>.from(e as Map)),
              )
              .toList(),
        ),
        activeId: decoded['activeId'] as String? ?? '',
      ),
    );
  }

  @override
  Future<void> save(ImageStoreSnapshot snapshot) async {
    final prepared = prepareImagePersistPayload(snapshot);
    final payload = <String, dynamic>{
      'activeId': prepared.activeId,
      'sessions': prepared.sessions.map((s) => s.toJson()).toList(),
    };
    await _history.save(jsonEncode(payload));
  }
}

/// Per-session file history; prefs implementation remains the legacy reader.
class FileImageSessionStorage
    implements
        ImageSessionStorage,
        RecoverableHistoryStorage<ImageStoreSnapshot> {
  FileImageSessionStorage({
    Future<Directory> Function()? root,
    SharedPreferences? prefs,
    HistoryFileAccess files = const HistoryFileAccess(),
  }) {
    final legacy = PrefsImageSessionStorage(prefs: prefs);
    _store = FileHistorySnapshotStore<ImageStoreSnapshot>(
      scope: 'image',
      legacyKey: PrefsImageSessionStorage.prefsKey,
      legacyLoad: legacy.load,
      decode: PrefsImageSessionStorage._decode,
      encode: _encode,
      empty: const ImageStoreSnapshot(sessions: [], activeId: ''),
      root: root,
      prefs: prefs == null ? null : () async => prefs,
      files: files,
    );
  }
  late final FileHistorySnapshotStore<ImageStoreSnapshot> _store;
  @override
  HistoryRecoveryState get recoveryState => _store.recoveryState;
  @override
  bool get writesBlocked => _store.writesBlocked;
  @override
  Future<ImageStoreSnapshot> load() => _store.load();
  @override
  Future<ImageStoreSnapshot> recover() => _store.recover();
  @override
  Future<void> save(ImageStoreSnapshot snapshot) => _store.save(snapshot);
  @override
  Future<void> replaceHistory(ImageStoreSnapshot snapshot) =>
      _store.replaceHistory(snapshot);
  @override
  Future<void> clearHistory(ImageStoreSnapshot empty) =>
      _store.clearHistory(empty);
  static Future<String> _encode(ImageStoreSnapshot snapshot) async {
    final prepared = prepareImagePersistPayload(snapshot);
    return jsonEncode({
      'activeId': prepared.activeId,
      'sessions': prepared.sessions.map((s) => s.toJson()).toList(),
    });
  }
}

/// 内存存储（单元测试）。
class MemoryImageSessionStorage implements ImageSessionStorage {
  MemoryImageSessionStorage([ImageStoreSnapshot? initial])
    : _snapshot =
          initial ?? const ImageStoreSnapshot(sessions: [], activeId: '');

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
