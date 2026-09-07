import 'package:flutter/foundation.dart';

import '../util/id.dart';
import 'video_asset_store.dart';
import 'video_models.dart';
import 'video_session_storage.dart';

/// 生视频会话仓库：CRUD、loading 条目、完成/失败/放弃、hydrate。
class VideoSessionRepository extends ChangeNotifier {
  VideoSessionRepository({
    required VideoSessionStorage storage,
    VideoAssetStore? assetStore,
  })  : _storage = storage,
        _assetStore = assetStore ?? MemoryVideoAssetStore();

  final VideoSessionStorage _storage;
  final VideoAssetStore _assetStore;

  VideoAssetStore get assetStore => _assetStore;

  List<VideoSession> _sessions = const [];
  String _activeId = '';
  bool _loaded = false;
  bool _loading = false;
  String? _lastError;

  bool get isLoaded => _loaded;
  bool get isLoading => _loading;
  String? get lastError => _lastError;

  List<VideoSession> get sessions => List.unmodifiable(_sessions);

  List<VideoSession> get sortedSessions {
    final list = List<VideoSession>.from(_sessions);
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  String get activeId => _activeId;

  VideoSession? get activeSession {
    if (_sessions.isEmpty) return null;
    for (final s in _sessions) {
      if (s.id == _activeId) return s;
    }
    return _sessions.first;
  }

  /// 待恢复条目。
  List<({String sessionId, VideoItem item})> get pendingResumeItems {
    final list = <({String sessionId, VideoItem item})>[];
    for (final session in _sessions) {
      for (final item in session.items) {
        if (item.needsResume &&
            (item.jobId?.trim().isNotEmpty ?? false) &&
            (item.status == VideoItemStatus.pendingResume ||
                item.status == VideoItemStatus.loading)) {
          list.add((sessionId: session.id, item: item));
        }
      }
    }
    return list;
  }

  int _now() => DateTime.now().millisecondsSinceEpoch;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _lastError = null;
    notifyListeners();
    try {
      final snap = await _storage.load();
      _sessions = List<VideoSession>.from(snap.sessions);
      _activeId = snap.activeId;
      if (_sessions.isEmpty) {
        final session = _newSession();
        _sessions = [session];
        _activeId = session.id;
        await _persist();
      } else if (!_sessions.any((s) => s.id == _activeId)) {
        _activeId = _sessions.first.id;
        await _persist();
      }
      _loaded = true;
    } catch (e) {
      _lastError = '加载生视频会话失败：$e';
      if (_sessions.isEmpty) {
        final session = _newSession();
        _sessions = [session];
        _activeId = session.id;
        _loaded = true;
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    await _storage.save(
      VideoStoreSnapshot(sessions: _sessions, activeId: _activeId),
    );
  }

  VideoSession _newSession([String title = '新视频']) {
    final now = _now();
    return VideoSession(
      id: createId('vid'),
      title: title,
      createdAt: now,
      updatedAt: now,
    );
  }

  int _indexOf(String id) => _sessions.indexWhere((s) => s.id == id);

  void _replace(int index, VideoSession next) {
    final list = List<VideoSession>.from(_sessions);
    list[index] = next;
    _sessions = list;
  }

  Future<VideoSession> createSession({String title = '新视频'}) async {
    final session = _newSession(title);
    _sessions = [session, ..._sessions];
    _activeId = session.id;
    await _persist();
    notifyListeners();
    return session;
  }

  Future<void> setActive(String id) async {
    if (!_sessions.any((s) => s.id == id)) return;
    _activeId = id;
    await _persist();
    notifyListeners();
  }

  Future<void> renameSession(String id, String title) async {
    final index = _indexOf(id);
    if (index < 0) return;
    final t = title.trim().isEmpty ? '新视频' : title.trim();
    _replace(
      index,
      _sessions[index].copyWith(title: t, updatedAt: _now()),
    );
    await _persist();
    notifyListeners();
  }

  Future<void> removeSession(String id) async {
    final target = _sessions.where((s) => s.id == id).firstOrNull;
    if (target != null) {
      await _deleteItemAssets(target.items);
    }
    _sessions = _sessions.where((s) => s.id != id).toList();
    if (_sessions.isEmpty) {
      final session = _newSession();
      _sessions = [session];
      _activeId = session.id;
    } else if (_activeId == id) {
      _activeId = _sessions.first.id;
    }
    await _persist();
    notifyListeners();
  }

  Future<void> clearItems(String id) async {
    final index = _indexOf(id);
    if (index < 0) return;
    await _deleteItemAssets(_sessions[index].items);
    _replace(
      index,
      _sessions[index].copyWith(items: const [], updatedAt: _now()),
    );
    await _persist();
    notifyListeners();
  }

  /// 用快照整体替换（导入备份用）；不迁移媒体二进制。
  Future<void> replaceAll(VideoStoreSnapshot snapshot) async {
    await _deleteItemAssets(
      _sessions.expand((s) => s.items).toList(),
    );
    var sessions = List<VideoSession>.from(snapshot.sessions);
    var activeId = snapshot.activeId;
    if (sessions.isEmpty) {
      final session = _newSession();
      sessions = [session];
      activeId = session.id;
    } else if (!sessions.any((s) => s.id == activeId)) {
      activeId = sessions.first.id;
    }
    _sessions = sessions;
    _activeId = activeId;
    _loaded = true;
    await _persist();
    notifyListeners();
  }

  /// 清除全部生视频会话与关联本地媒体文件。幂等。
  Future<void> clearAllSessions({bool clearMediaCache = true}) async {
    await _deleteItemAssets(
      _sessions.expand((s) => s.items).toList(),
    );
    if (clearMediaCache) {
      try {
        await _assetStore.clearAll();
      } catch (_) {}
    }
    final session = _newSession();
    _sessions = [session];
    _activeId = session.id;
    await _persist();
    notifyListeners();
  }

  /// 追加 loading 条目；首条非空 prompt 截 24 字作 title。
  Future<VideoItem?> appendLoadingItem(
    String sessionId, {
    required VideoGenMode mode,
    required String prompt,
    String model = '',
    String providerId = '',
    String providerName = '',
    int? duration,
    String? size,
    String? aspectRatio,
    String? resolution,
    String? refPreview,
    String? id,
    int? createdAt,
  }) async {
    final index = _indexOf(sessionId);
    if (index < 0) return null;
    final session = _sessions[index];
    final item = VideoItem(
      id: id ?? createId('vgen'),
      createdAt: createdAt ?? _now(),
      mode: mode,
      prompt: prompt,
      model: model,
      providerId: providerId,
      providerName: providerName,
      duration: duration,
      size: size,
      aspectRatio: aspectRatio,
      resolution: resolution,
      refPreview: refPreview,
      status: VideoItemStatus.loading,
      progress: 0,
      needsResume: false,
    );
    var title = session.title;
    if (title == '新视频' && prompt.trim().isNotEmpty) {
      final slice = prompt.trim();
      title = slice.length <= 24 ? slice : slice.substring(0, 24);
    }
    _replace(
      index,
      session.copyWith(
        items: [...session.items, item],
        title: title,
        updatedAt: _now(),
      ),
    );
    await _persist();
    notifyListeners();
    return item;
  }

  Future<void> updateItem(
    String sessionId,
    String itemId, {
    VideoItemStatus? status,
    String? jobId,
    double? progress,
    String? videoUrl,
    String? remoteVideoUrl,
    String? localPath,
    String? errorMessage,
    bool? needsResume,
    bool? needsMaterialize,
    bool clearJobId = false,
    bool clearProgress = false,
    bool clearVideoUrl = false,
    bool clearRemoteVideoUrl = false,
    bool clearLocalPath = false,
    bool clearErrorMessage = false,
    bool persist = true,
  }) async {
    final index = _indexOf(sessionId);
    if (index < 0) return;
    final session = _sessions[index];
    final itemIndex = session.items.indexWhere((i) => i.id == itemId);
    if (itemIndex < 0) return;
    final prev = session.items[itemIndex];
    final nextVideoUrl =
        (videoUrl != null && videoUrl == prev.videoUrl) ? null : videoUrl;
    final nextRemoteVideoUrl =
        (remoteVideoUrl != null && remoteVideoUrl == prev.remoteVideoUrl)
            ? null
            : remoteVideoUrl;
    final nextLocalPath =
        (localPath != null && localPath == prev.localPath) ? null : localPath;
    var next = prev.copyWith(
      status: status,
      jobId: jobId,
      progress: progress,
      videoUrl: nextVideoUrl,
      remoteVideoUrl: nextRemoteVideoUrl,
      localPath: nextLocalPath,
      errorMessage: errorMessage,
      needsResume: needsResume,
      needsMaterialize: needsMaterialize,
      clearJobId: clearJobId,
      clearProgress: clearProgress,
      clearVideoUrl: clearVideoUrl,
      clearRemoteVideoUrl: clearRemoteVideoUrl,
      clearLocalPath: clearLocalPath,
      clearErrorMessage: clearErrorMessage,
    );
    // 禁止用空串清掉已有 https remoteVideoUrl
    final prevRemote = prev.remoteVideoUrl;
    if (prevRemote != null &&
        RegExp(r'^https?://', caseSensitive: false).hasMatch(prevRemote) &&
        (next.remoteVideoUrl == null ||
            !RegExp(r'^https?://', caseSensitive: false)
                .hasMatch(next.remoteVideoUrl!))) {
      next = next.copyWith(remoteVideoUrl: prevRemote);
    }
    if (_itemPlaybackFieldsEqual(prev, next)) {
      return;
    }
    final items = List<VideoItem>.from(session.items);
    items[itemIndex] = next;
    _replace(
      index,
      session.copyWith(items: items, updatedAt: _now()),
    );
    if (persist) await _persist();
    notifyListeners();
  }

  static bool _itemPlaybackFieldsEqual(VideoItem a, VideoItem b) {
    return a.status == b.status &&
        a.jobId == b.jobId &&
        a.progress == b.progress &&
        a.videoUrl == b.videoUrl &&
        a.remoteVideoUrl == b.remoteVideoUrl &&
        a.localPath == b.localPath &&
        a.errorMessage == b.errorMessage &&
        a.needsResume == b.needsResume &&
        a.needsMaterialize == b.needsMaterialize;
  }

  Future<void> completeItem(
    String sessionId,
    String itemId, {
    required String videoUrl,
    String? remoteVideoUrl,
    String? localPath,
    double progress = 100,
    bool needsMaterialize = false,
  }) async {
    await updateItem(
      sessionId,
      itemId,
      status: VideoItemStatus.success,
      videoUrl: videoUrl,
      remoteVideoUrl: remoteVideoUrl,
      localPath: localPath,
      progress: progress,
      needsResume: false,
      needsMaterialize: needsMaterialize,
      clearErrorMessage: true,
    );
  }

  Future<void> failItem(
    String sessionId,
    String itemId,
    String errorMessage, {
    bool needsResume = false,
    bool needsMaterialize = false,
    String? remoteVideoUrl,
    VideoItemStatus status = VideoItemStatus.error,
  }) async {
    await updateItem(
      sessionId,
      itemId,
      status: status,
      errorMessage: errorMessage,
      needsResume: needsResume,
      needsMaterialize: needsMaterialize,
      remoteVideoUrl: remoteVideoUrl,
    );
  }

  /// 已生成但不可播：保留 remote/jobId，露出「重新加载」。
  Future<void> markNeedsMaterialize(
    String sessionId,
    String itemId, {
    String? errorMessage,
    String? remoteVideoUrl,
    String? videoUrl,
    String? jobId,
  }) async {
    await updateItem(
      sessionId,
      itemId,
      status: VideoItemStatus.error,
      needsResume: false,
      needsMaterialize: true,
      progress: 100,
      remoteVideoUrl: remoteVideoUrl,
      videoUrl: videoUrl,
      jobId: jobId,
      errorMessage:
          errorMessage ?? '视频已生成但本地加载失败，可尝试重新加载',
    );
  }

  /// 放弃 pending_resume。
  Future<void> abandonItem(String sessionId, String itemId) async {
    final session = _sessions.where((s) => s.id == sessionId).firstOrNull;
    final item = session?.items.where((i) => i.id == itemId).firstOrNull;
    await updateItem(
      sessionId,
      itemId,
      status: VideoItemStatus.abandoned,
      needsResume: false,
      errorMessage: item?.errorMessage?.isNotEmpty == true
          ? item!.errorMessage
          : '已放弃恢复',
    );
  }

  /// 标记为可恢复（停止轮询后）。
  Future<void> markPendingResume(
    String sessionId,
    String itemId, {
    String? errorMessage,
  }) async {
    await updateItem(
      sessionId,
      itemId,
      status: VideoItemStatus.pendingResume,
      needsResume: true,
      errorMessage: errorMessage ?? '已停止轮询，可手动恢复',
    );
  }

  Future<void> _deleteItemAssets(List<VideoItem> items) async {
    for (final item in items) {
      final path = item.localPath ?? item.videoUrl;
      if (path != null &&
          path.isNotEmpty &&
          !path.startsWith('http') &&
          !path.startsWith('data:')) {
        try {
          await _assetStore.delete(path);
        } catch (_) {}
      }
    }
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
