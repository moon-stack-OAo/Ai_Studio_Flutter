import 'package:flutter/foundation.dart';

import '../settings/history_snapshot_store.dart';
import '../settings/asset_reference_guard.dart';

import '../prompt/custom_skills.dart';

import '../util/id.dart';
import 'image_asset_store.dart';
import 'image_models.dart';
import 'image_session_storage.dart';

/// 生图会话仓库：CRUD、loading 条目、完成/失败、hydrate、可选落盘。
class ImageSessionRepository extends ChangeNotifier {
  ImageSessionRepository({
    required ImageSessionStorage storage,
    AssetReferenceGuard? assetReferences,
    ImageAssetStore? assetStore,
  }) : _storage = storage,
       _assetStore = assetStore ?? MemoryImageAssetStore(),
       _assetReferences = assetReferences {
    assetReferences?.register(this, () {
      if (!_loaded || _loading || writesBlocked || _lastError != null) {
        throw const HistoryStorageException();
      }
      return {
        for (final s in _sessions)
          for (final i in s.items)
            for (final ref in [...i.images, ...i.referenceImages])
              if (ref.type == ImageRefType.file) ref.src,
      };
    });
  }

  final AssetReferenceGuard? _assetReferences;

  final ImageSessionStorage _storage;
  final ImageAssetStore _assetStore;

  ImageAssetStore get assetStore => _assetStore;

  List<ImageSession> _sessions = const [];
  String _activeId = '';
  bool _loaded = false;
  bool _loading = false;
  String? _lastError;

  RecoverableHistoryStorage<ImageStoreSnapshot>? get _recovery =>
      _storage is RecoverableHistoryStorage<ImageStoreSnapshot>
      ? _storage as RecoverableHistoryStorage<ImageStoreSnapshot>
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
    required String itemId,
  }) async {
    try {
      _assertWritable();
    } catch (_) {
      _finishUnstarted(sessionId, itemId);
      notifyListeners();
      rethrow;
    }
    _activeGenerations++;
    try {
      return await action();
    } finally {
      _activeGenerations--;
      _finishUnstarted(sessionId, itemId);
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
                item.status == ImageItemStatus.loading)
              item.copyWith(
                status: ImageItemStatus.error,
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
          (s) => s.items.any((i) => i.status == ImageItemStatus.loading),
        )) {
      throw const HistoryStorageException();
    }
    _loading = true;
    notifyListeners();
    try {
      final snapshot = await recovery.recover();
      _sessions = List<ImageSession>.from(snapshot.sessions);
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

  List<ImageSession> get sessions => List.unmodifiable(_sessions);

  List<ImageSession> get sortedSessions {
    final list = List<ImageSession>.from(_sessions);
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  String get activeId => _activeId;

  ImageSession? get activeSession {
    if (_sessions.isEmpty) return null;
    for (final s in _sessions) {
      if (s.id == _activeId) return s;
    }
    return _sessions.first;
  }

  int _now() => DateTime.now().millisecondsSinceEpoch;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _lastError = null;
    notifyListeners();
    try {
      final snap = await _storage.load();
      _sessions = List<ImageSession>.from(snap.sessions);
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
          ImageStoreSnapshot(sessions: _sessions, activeId: _activeId),
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
      ImageStoreSnapshot(sessions: _sessions, activeId: _activeId),
    );
  }

  ImageSession _newSession([String title = '新生图']) {
    final now = _now();
    return ImageSession(
      id: createId('img'),
      title: title,
      createdAt: now,
      updatedAt: now,
    );
  }

  int _indexOf(String id) => _sessions.indexWhere((s) => s.id == id);

  void _replace(int index, ImageSession next) {
    final list = List<ImageSession>.from(_sessions);
    list[index] = next;
    _sessions = list;
  }

  Future<ImageSession> createSession({String title = '新生图'}) async {
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
    final t = title.trim().isEmpty ? '新生图' : title.trim();
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
    ImageStoreSnapshot snapshot, {
    bool deleteAssets = true,
  }) async {
    _assertWritable();
    _assetReferences?.retainedByOthers(this);
    final removedAssets = _sessions.expand((s) => s.items).toList();
    var sessions = List<ImageSession>.from(snapshot.sessions);
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
  Future<void> cleanupReplacedAssets(List<ImageSession> previous) =>
      _deleteItemAssets(previous.expand((s) => s.items).toList());

  /// 清除全部生图会话与关联本地媒体文件。幂等。
  Future<void> clearAllSessions({
    bool clearMediaCache = true,
    bool deleteAssets = true,
  }) async {
    if (_loading || _destructive) throw const HistoryStorageException();
    if (deleteAssets) _assetReferences?.retainedByOthers(this);
    _destructive = true;
    try {
      final empty = ImageStoreSnapshot(sessions: const [], activeId: '');
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
  Future<ImageItem?> appendLoadingItem(
    String sessionId, {
    required ImageGenMode mode,
    required String prompt,
    String? finalPrompt,
    List<SkillSnapshot> appliedSkills = const [],
    String model = '',
    String providerName = '',
    int n = 1,
    String? size,
    String? aspectRatio,
    String? quality,
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
    final item = ImageItem(
      id: id ?? createId('imgi'),
      createdAt: createdAt ?? _now(),
      mode: mode,
      prompt: prompt,
      finalPrompt: finalPrompt,
      appliedSkills: List.unmodifiable(appliedSkills),
      model: model,
      providerName: providerName,
      n: n,
      size: size,
      aspectRatio: aspectRatio,
      quality: quality,
      referenceImages: refs,
      refPreview: refPreview,
      status: ImageItemStatus.loading,
    );
    var title = session.title;
    if (title == '新生图' && prompt.trim().isNotEmpty) {
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
    List<ImageRef>? images,
    List<ImageRef>? referenceImages,
    ImageItemStatus? status,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? refPreview,
    bool clearRefPreview = false,
  }) async {
    _assertWritable();
    final index = _indexOf(sessionId);
    if (index < 0) return;
    final session = _sessions[index];
    final itemIndex = session.items.indexWhere((i) => i.id == itemId);
    if (itemIndex < 0) return;
    final items = List<ImageItem>.from(session.items);
    final cappedRefs = referenceImages == null
        ? null
        : (referenceImages.length > maxTurnReferenceImages
              ? referenceImages.sublist(0, maxTurnReferenceImages)
              : referenceImages);
    items[itemIndex] = items[itemIndex].copyWith(
      images: images,
      referenceImages: cappedRefs,
      status: status,
      errorMessage: errorMessage,
      clearErrorMessage: clearErrorMessage,
      refPreview: refPreview,
      clearRefPreview: clearRefPreview,
    );
    _replace(index, session.copyWith(items: items, updatedAt: _now()));
    await _persist();
    notifyListeners();
  }

  /// 完成：优先将 b64 落到 [assetStore]，条目存 type:file。
  Future<void> completeItem(
    String sessionId,
    String itemId,
    List<ImageRef> images,
  ) async {
    _assertWritable();
    final stored = await _persistImages(itemId, images);
    await updateItem(
      sessionId,
      itemId,
      images: stored,
      status: ImageItemStatus.done,
      clearErrorMessage: true,
    );
  }

  Future<void> failItem(
    String sessionId,
    String itemId,
    String errorMessage,
  ) async {
    _assertWritable();
    await updateItem(
      sessionId,
      itemId,
      status: ImageItemStatus.error,
      errorMessage: errorMessage,
    );
  }

  Future<List<ImageRef>> _persistImages(
    String itemId,
    List<ImageRef> images,
  ) async {
    final out = <ImageRef>[];
    for (var i = 0; i < images.length; i++) {
      final img = images[i];
      if (img.type == ImageRefType.b64) {
        final bytes = decodeImageB64(img.src);
        if (bytes != null && bytes.isNotEmpty) {
          final path = await _assetStore.savePng(bytes, '${itemId}_$i');
          out.add(
            ImageRef(
              type: ImageRefType.file,
              src: path,
              revisedPrompt: img.revisedPrompt,
            ),
          );
          continue;
        }
      }
      out.add(img);
    }
    return out;
  }

  Future<void> _deleteItemAssets(
    List<ImageItem> items, {
    bool retainCurrent = true,
  }) async {
    final retained = retainCurrent
        ? _sessions
              .expand((s) => s.items)
              .expand((i) => [...i.images, ...i.referenceImages])
              .where((i) => i.type == ImageRefType.file)
              .map((i) => assetReferenceKey(i.src))
              .toSet()
        : <String>{};
    final others = _assetReferences?.retainedByOthers(this) ?? <String>{};
    retained.addAll(others);
    for (final item in items) {
      for (final img in [...item.images, ...item.referenceImages]) {
        if (img.type == ImageRefType.file &&
            img.src.isNotEmpty &&
            !retained.contains(assetReferenceKey(img.src))) {
          try {
            await _assetStore.delete(img.src);
          } catch (_) {}
        }
      }
    }
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
      final path = await _assetStore.savePng(bytes, '${itemId}_ref_$i');
      out.add(ImageRef(type: ImageRefType.file, src: path));
    }
    return out;
  }

  /// 读取条目图片字节（file / b64）；url 返回 null。
  Future<Uint8List?> readImageBytes(ImageRef ref) async {
    switch (ref.type) {
      case ImageRefType.file:
        return _assetStore.read(ref.src);
      case ImageRefType.b64:
        return decodeImageB64(ref.src);
      case ImageRefType.url:
        return null;
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
