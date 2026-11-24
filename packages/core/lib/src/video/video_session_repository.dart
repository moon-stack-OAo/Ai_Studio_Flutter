import 'package:flutter/foundation.dart';

import '../settings/history_snapshot_store.dart';
import '../settings/asset_reference_guard.dart';

import '../image/image_asset_store.dart';
import '../image/image_models.dart';
import '../prompt/custom_skills.dart';
import '../util/id.dart';
import 'video_asset_store.dart';
import 'video_models.dart';
import 'video_session_storage.dart';

/// 生视频会话仓库：CRUD、loading 条目、完成/失败/放弃、hydrate。
class VideoSessionRepository extends ChangeNotifier {
  VideoSessionRepository({
    required VideoSessionStorage storage,
    AssetReferenceGuard? assetReferences,
    VideoAssetStore? assetStore,
    ImageAssetStore? referenceImageStore,
  }) : _storage = storage,
       _assetStore = assetStore ?? MemoryVideoAssetStore(),
       _referenceImageStore = referenceImageStore ?? MemoryImageAssetStore(),
       _assetReferences = assetReferences {
    assetReferences?.register(this, () {
      if (!_loaded || _loading || writesBlocked || _lastError != null) {
        throw const HistoryStorageException();
      }
      return {
        for (final s in _sessions)
          for (final i in s.items)
            for (final ref in i.referenceImages)
              if (ref.type == ImageRefType.file) ref.src,
        for (final s in _sessions)
          for (final i in s.items) ...[
            if (i.localPath != null) i.localPath!,
            if (i.videoUrl != null) i.videoUrl!,
            if (i.posterLocalPath != null) i.posterLocalPath!,
          ],
      };
    });
  }

  final AssetReferenceGuard? _assetReferences;

  final VideoSessionStorage _storage;
  final VideoAssetStore _assetStore;
  final ImageAssetStore _referenceImageStore;

  VideoAssetStore get assetStore => _assetStore;

  ImageAssetStore get referenceImageStore => _referenceImageStore;

  List<VideoSession> _sessions = const [];
  String _activeId = '';
  bool _loaded = false;
  bool _loading = false;
  String? _lastError;

  RecoverableHistoryStorage<VideoStoreSnapshot>? get _recovery =>
      _storage is RecoverableHistoryStorage<VideoStoreSnapshot>
      ? _storage as RecoverableHistoryStorage<VideoStoreSnapshot>
      : null;
  HistoryRecoveryState get recoveryState =>
      _recovery?.recoveryState ?? HistoryRecoveryState.healthy;
  bool get writesBlocked => _recovery?.writesBlocked ?? false;
  bool _destructive = false;
  void _assertWritable() {
    if (_destructive || _loading || writesBlocked) {
      throw const HistoryStorageException();
    }
  }

  int _activeGenerations = 0;

  /// A repository lease excludes recovery even after a completion changed the
  /// visible status. Always release locally; never rewrite an authoritative journal.
  Future<T> runGeneration<T>(
    String sessionId,
    Future<T> Function() action, {
    String? itemId,
    List<({String sessionId, String itemId})> items = const [],
  }) async {
    try {
      _assertWritable();
    } catch (_) {
      if (itemId != null) _finishUnstarted(sessionId, itemId);
      notifyListeners();
      rethrow;
    }
    _activeGenerations++;
    try {
      return await action();
    } finally {
      _activeGenerations--;
      if (itemId != null) _finishUnstarted(sessionId, itemId);
      for (final item in items) {
        _finishUnstarted(item.sessionId, item.itemId);
      }
      notifyListeners();
    }
  }

  void _finishUnstarted(String sessionId, String? itemId) {
    final index = _indexOf(sessionId);
    if (index < 0) return;
    final session = _sessions[index];
    _replace(
      index,
      session.copyWith(
        items: [
          for (final item in session.items)
            if ((itemId == null || item.id == itemId) &&
                item.status == VideoItemStatus.loading)
              item.copyWith(
                status: VideoItemStatus.error,
                errorMessage: '生成未完成；请恢复历史后重试。',
              )
            else
              item,
        ],
      ),
    );
  }

  Future<void> recoverHistory() async {
    final recovery = _recovery;
    if (recovery == null || !writesBlocked) return;
    if (_loading ||
        _activeGenerations > 0 ||
        _destructive ||
        _sessions.any(
          (s) => s.items.any((i) => i.status == VideoItemStatus.loading),
        )) {
      throw const HistoryStorageException();
    }
    _loading = true;
    notifyListeners();
    try {
      final snapshot = await recovery.recover();
      _sessions = List<VideoSession>.from(snapshot.sessions);
      _activeId = snapshot.activeId;
      if (_sessions.isEmpty) {
        final session = _newSession();
        _sessions = [session];
        _activeId = session.id;
      }
      _lastError = null;
    } catch (_) {
      _lastError = '历史恢复失败，原数据已保留。';
      rethrow;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

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
      _lastError = '历史读取失败，原数据已保留；请在设置中重试恢复。';
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

  Future<void> _persistRemoval() async {
    _destructive = true;
    try {
      if (_recovery != null) {
        await _recovery!.replaceHistory(
          VideoStoreSnapshot(sessions: _sessions, activeId: _activeId),
        );
      } else {
        await _persist();
      }
    } finally {
      _destructive = false;
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
    _assertWritable();
    final session = _newSession(title);
    _sessions = [session, ..._sessions];
    _activeId = session.id;
    await _persist();
    notifyListeners();
    return session;
  }

  Future<void> setActive(String id) async {
    _assertWritable();
    if (id == _activeId || !_sessions.any((s) => s.id == id)) return;
    _activeId = id;
    await _persist();
    notifyListeners();
  }

  Future<void> renameSession(String id, String title) async {
    _assertWritable();
    final index = _indexOf(id);
    if (index < 0) return;
    final t = title.trim().isEmpty ? '新视频' : title.trim();
    _replace(index, _sessions[index].copyWith(title: t, updatedAt: _now()));
    await _persist();
    notifyListeners();
  }

  Future<void> removeSession(String id) async {
    _assertWritable();
    _assetReferences?.retainedByOthers(this);
    final target = _sessions.where((s) => s.id == id).firstOrNull;

    _sessions = _sessions.where((s) => s.id != id).toList();
    if (_sessions.isEmpty) {
      final session = _newSession();
      _sessions = [session];
      _activeId = session.id;
    } else if (_activeId == id) {
      _activeId = _sessions.first.id;
    }
    await _persistRemoval();
    if (target != null) await _deleteItemAssets(target.items);
    notifyListeners();
  }

  Future<void> clearItems(String id) async {
    _assertWritable();
    _assetReferences?.retainedByOthers(this);
    final index = _indexOf(id);
    if (index < 0) return;
    final removedAssets = _sessions[index].items;
    _replace(
      index,
      _sessions[index].copyWith(items: const [], updatedAt: _now()),
    );
    await _persistRemoval();
    await _deleteItemAssets(removedAssets);
    notifyListeners();
  }

  /// 用快照整体替换（导入备份用）；不迁移媒体二进制。
  Future<void> replaceAll(
    VideoStoreSnapshot snapshot, {
    bool deleteAssets = true,
  }) async {
    _assertWritable();
    _assetReferences?.retainedByOthers(this);
    final removedAssets = _sessions.expand((s) => s.items).toList();
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
    await _persistRemoval();
    if (deleteAssets) await _deleteItemAssets(removedAssets);
    notifyListeners();
  }

  /// Import cleanup runs only after all selected stores have committed.
  Future<void> cleanupReplacedAssets(List<VideoSession> previous) =>
      _deleteItemAssets(previous.expand((s) => s.items).toList());

  /// 清除全部生视频会话与关联本地媒体文件。幂等。
  Future<void> clearAllSessions({
    bool clearMediaCache = true,
    bool deleteAssets = true,
  }) async {
    if (_loading || _destructive) throw const HistoryStorageException();
    if (deleteAssets) _assetReferences?.retainedByOthers(this);
    _destructive = true;
    try {
      final empty = VideoStoreSnapshot(sessions: const [], activeId: '');
      if (_recovery != null) {
        await _recovery!.clearHistory(empty);
      } else {
        await _storage.save(empty);
      }
      if (deleteAssets) {
        await _deleteItemAssets(
          _sessions.expand((s) => s.items).toList(),
          retainCurrent: false,
        );
        if (clearMediaCache) {
          try {
            final retained =
                _assetReferences?.retainedByOthers(this) ?? <String>{};
            if (retained.isEmpty) {
              await _assetStore.clearAll();
            } else if (_assetStore is SelectiveAssetClear) {
              await (_assetStore as SelectiveAssetClear).clearExcept(retained);
            }
          } catch (_) {}
          // 参考图可能与生图共用 ImageAssetStore；仅删本会话已知路径
          //（见 _deleteItemAssets），勿 clearAll 以免清空生图缓存。
        }
      }
      final session = _newSession();
      _sessions = [session];
      _activeId = session.id;
      await _persist();
      _loaded = true;
      _lastError = null;
      notifyListeners();
    } finally {
      _destructive = false;
    }
  }

  /// 追加 loading 条目；首条非空 prompt 截 24 字作 title。
  ///
  /// [referenceImages] 为本回合参考图资产（已落盘为 file 优先）；会截到
  /// [maxTurnReferenceImages]。
  Future<VideoItem?> appendLoadingItem(
    String sessionId, {
    required VideoGenMode mode,
    required String prompt,
    String? finalPrompt,
    List<SkillSnapshot> appliedSkills = const [],
    String model = '',
    String providerId = '',
    String providerName = '',
    int? duration,
    String? size,
    String? aspectRatio,
    String? resolution,
    List<ImageRef> referenceImages = const [],
    String? refPreview,
    String? id,
    int? createdAt,
  }) async {
    _assertWritable();
    final index = _indexOf(sessionId);
    if (index < 0) return null;
    final session = _sessions[index];
    final refs = referenceImages.length > maxTurnReferenceImages
        ? referenceImages.sublist(0, maxTurnReferenceImages)
        : List<ImageRef>.from(referenceImages);
    final item = VideoItem(
      id: id ?? createId('vgen'),
      createdAt: createdAt ?? _now(),
      mode: mode,
      prompt: prompt,
      finalPrompt: finalPrompt,
      appliedSkills: List.unmodifiable(appliedSkills),
      model: model,
      providerId: providerId,
      providerName: providerName,
      duration: duration,
      size: size,
      aspectRatio: aspectRatio,
      resolution: resolution,
      referenceImages: refs,
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
    try {
      await _persist();
    } catch (_) {
      // This append never handed a task to its caller. Only settle this ID in
      // memory: save may already have published its authoritative journal.
      _finishUnstarted(sessionId, item.id);
      notifyListeners();
      rethrow;
    }
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
    String? posterUrl,
    String? posterLocalPath,
    String? errorMessage,
    bool? needsResume,
    bool? needsMaterialize,
    bool clearJobId = false,
    bool clearProgress = false,
    bool clearVideoUrl = false,
    bool clearRemoteVideoUrl = false,
    bool clearLocalPath = false,
    bool clearPosterUrl = false,
    bool clearPosterLocalPath = false,
    bool clearErrorMessage = false,
    bool persist = true,
  }) async {
    _assertWritable();
    final index = _indexOf(sessionId);
    if (index < 0) return;
    final session = _sessions[index];
    final itemIndex = session.items.indexWhere((i) => i.id == itemId);
    if (itemIndex < 0) return;
    final prev = session.items[itemIndex];
    final nextVideoUrl = (videoUrl != null && videoUrl == prev.videoUrl)
        ? null
        : videoUrl;
    final nextRemoteVideoUrl =
        (remoteVideoUrl != null && remoteVideoUrl == prev.remoteVideoUrl)
        ? null
        : remoteVideoUrl;
    final nextLocalPath = (localPath != null && localPath == prev.localPath)
        ? null
        : localPath;
    final nextPosterUrl = (posterUrl != null && posterUrl == prev.posterUrl)
        ? null
        : posterUrl;
    final nextPosterLocalPath =
        (posterLocalPath != null && posterLocalPath == prev.posterLocalPath)
        ? null
        : posterLocalPath;
    var next = prev.copyWith(
      status: status,
      jobId: jobId,
      progress: progress,
      videoUrl: nextVideoUrl,
      remoteVideoUrl: nextRemoteVideoUrl,
      localPath: nextLocalPath,
      posterUrl: nextPosterUrl,
      posterLocalPath: nextPosterLocalPath,
      errorMessage: errorMessage,
      needsResume: needsResume,
      needsMaterialize: needsMaterialize,
      clearJobId: clearJobId,
      clearProgress: clearProgress,
      clearVideoUrl: clearVideoUrl,
      clearRemoteVideoUrl: clearRemoteVideoUrl,
      clearLocalPath: clearLocalPath,
      clearPosterUrl: clearPosterUrl,
      clearPosterLocalPath: clearPosterLocalPath,
      clearErrorMessage: clearErrorMessage,
    );
    // 禁止用空串清掉已有 https remoteVideoUrl
    final prevRemote = prev.remoteVideoUrl;
    if (prevRemote != null &&
        RegExp(r'^https?://', caseSensitive: false).hasMatch(prevRemote) &&
        (next.remoteVideoUrl == null ||
            !RegExp(
              r'^https?://',
              caseSensitive: false,
            ).hasMatch(next.remoteVideoUrl!))) {
      next = next.copyWith(remoteVideoUrl: prevRemote);
    }
    if (_itemPlaybackFieldsEqual(prev, next)) {
      return;
    }
    final items = List<VideoItem>.from(session.items);
    items[itemIndex] = next;
    _replace(index, session.copyWith(items: items, updatedAt: _now()));
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
        a.posterUrl == b.posterUrl &&
        a.posterLocalPath == b.posterLocalPath &&
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
    String? posterUrl,
    String? posterLocalPath,
    double progress = 100,
    bool needsMaterialize = false,
  }) async {
    _assertWritable();
    await updateItem(
      sessionId,
      itemId,
      status: VideoItemStatus.success,
      videoUrl: videoUrl,
      remoteVideoUrl: remoteVideoUrl,
      localPath: localPath,
      posterUrl: posterUrl,
      posterLocalPath: posterLocalPath,
      progress: progress,
      needsResume: false,
      needsMaterialize: needsMaterialize,
      clearErrorMessage: true,
    );
  }

  /// 写入本机抽帧封面路径（不清空已有远程 posterUrl）。
  Future<void> setPosterLocalPath(
    String sessionId,
    String itemId,
    String path,
  ) async {
    _assertWritable();
    final trimmed = path.trim();
    if (trimmed.isEmpty) return;
    await updateItem(sessionId, itemId, posterLocalPath: trimmed);
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
    _assertWritable();
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
    _assertWritable();
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
      errorMessage: errorMessage ?? '视频已生成但本地加载失败，可尝试重新加载',
    );
  }

  /// 放弃 pending_resume。
  Future<void> abandonItem(String sessionId, String itemId) async {
    _assertWritable();
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
    _assertWritable();
    await updateItem(
      sessionId,
      itemId,
      status: VideoItemStatus.pendingResume,
      needsResume: true,
      errorMessage: errorMessage ?? '已停止轮询，可手动恢复',
    );
  }

  /// 将参考图字节落盘为会话资产，返回 file 型 [ImageRef] 列表。
  Future<List<ImageRef>> persistReferenceImages(
    String itemId,
    List<Uint8List> byteList,
  ) async {
    _assertWritable();
    final out = <ImageRef>[];
    final limit = byteList.length > maxTurnReferenceImages
        ? maxTurnReferenceImages
        : byteList.length;
    for (var i = 0; i < limit; i++) {
      final bytes = byteList[i];
      if (bytes.isEmpty) continue;
      final path = await _referenceImageStore.savePng(
        bytes,
        'vref_${itemId}_$i',
      );
      out.add(ImageRef(type: ImageRefType.file, src: path));
    }
    return out;
  }

  /// 读取参考图字节（file / b64）；url 返回 null。
  Future<Uint8List?> readReferenceImageBytes(ImageRef ref) async {
    switch (ref.type) {
      case ImageRefType.file:
        return _referenceImageStore.read(ref.src);
      case ImageRefType.b64:
        return decodeImageB64(ref.src);
      case ImageRefType.url:
        return null;
    }
  }

  Future<void> _deleteItemAssets(
    List<VideoItem> items, {
    bool retainCurrent = true,
  }) async {
    final retained = retainCurrent
        ? _sessions
              .expand((s) => s.items)
              .map((i) => i.localPath ?? i.videoUrl)
              .whereType<String>()
              .map(assetReferenceKey)
              .toSet()
        : <String>{};
    final retainedRefs = retainCurrent
        ? _sessions
              .expand((s) => s.items)
              .expand((i) => i.referenceImages)
              .where((i) => i.type == ImageRefType.file)
              .map((i) => assetReferenceKey(i.src))
              .toSet()
        : <String>{};
    final others = _assetReferences?.retainedByOthers(this) ?? <String>{};
    if (retainCurrent) {
      retained.addAll(retainedRefs);
      retained.addAll(
        _sessions
            .expand((s) => s.items)
            .expand(
              (i) => [
                if (i.videoUrl != null) assetReferenceKey(i.videoUrl!),
                if (i.posterLocalPath != null)
                  assetReferenceKey(i.posterLocalPath!),
              ],
            ),
      );
      retainedRefs.addAll(retained);
    }
    retained.addAll(others);
    retainedRefs.addAll(others);
    for (final item in items) {
      final path = item.localPath ?? item.videoUrl;
      if (path != null &&
          path.isNotEmpty &&
          !retained.contains(assetReferenceKey(path)) &&
          !path.startsWith('http') &&
          !path.startsWith('data:')) {
        try {
          await _assetStore.delete(path);
        } catch (_) {}
      }
      for (final img in item.referenceImages) {
        if (img.type == ImageRefType.file &&
            img.src.isNotEmpty &&
            !retainedRefs.contains(assetReferenceKey(img.src))) {
          try {
            await _referenceImageStore.delete(img.src);
          } catch (_) {}
        }
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
