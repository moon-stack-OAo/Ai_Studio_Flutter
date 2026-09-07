import 'package:flutter/foundation.dart';

import '../util/id.dart';
import 'image_asset_store.dart';
import 'image_models.dart';
import 'image_session_storage.dart';

/// 生图会话仓库：CRUD、loading 条目、完成/失败、hydrate、可选落盘。
class ImageSessionRepository extends ChangeNotifier {
  ImageSessionRepository({
    required ImageSessionStorage storage,
    ImageAssetStore? assetStore,
  })  : _storage = storage,
        _assetStore = assetStore ?? MemoryImageAssetStore();

  final ImageSessionStorage _storage;
  final ImageAssetStore _assetStore;

  ImageAssetStore get assetStore => _assetStore;

  List<ImageSession> _sessions = const [];
  String _activeId = '';
  bool _loaded = false;
  bool _loading = false;
  String? _lastError;

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
      _lastError = '加载生图会话失败：$e';
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
    final t = title.trim().isEmpty ? '新生图' : title.trim();
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
  Future<void> replaceAll(ImageStoreSnapshot snapshot) async {
    await _deleteItemAssets(
      _sessions.expand((s) => s.items).toList(),
    );
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
    await _persist();
    notifyListeners();
  }

  /// 清除全部生图会话与关联本地媒体文件。幂等。
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
  Future<ImageItem?> appendLoadingItem(
    String sessionId, {
    required ImageGenMode mode,
    required String prompt,
    String model = '',
    String providerName = '',
    int n = 1,
    String? size,
    String? aspectRatio,
    String? quality,
    String? refPreview,
    String? id,
    int? createdAt,
  }) async {
    final index = _indexOf(sessionId);
    if (index < 0) return null;
    final session = _sessions[index];
    final item = ImageItem(
      id: id ?? createId('imgi'),
      createdAt: createdAt ?? _now(),
      mode: mode,
      prompt: prompt,
      model: model,
      providerName: providerName,
      n: n,
      size: size,
      aspectRatio: aspectRatio,
      quality: quality,
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
    await _persist();
    notifyListeners();
    return item;
  }

  Future<void> updateItem(
    String sessionId,
    String itemId, {
    List<ImageRef>? images,
    ImageItemStatus? status,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? refPreview,
    bool clearRefPreview = false,
  }) async {
    final index = _indexOf(sessionId);
    if (index < 0) return;
    final session = _sessions[index];
    final itemIndex = session.items.indexWhere((i) => i.id == itemId);
    if (itemIndex < 0) return;
    final items = List<ImageItem>.from(session.items);
    items[itemIndex] = items[itemIndex].copyWith(
      images: images,
      status: status,
      errorMessage: errorMessage,
      clearErrorMessage: clearErrorMessage,
      refPreview: refPreview,
      clearRefPreview: clearRefPreview,
    );
    _replace(
      index,
      session.copyWith(items: items, updatedAt: _now()),
    );
    await _persist();
    notifyListeners();
  }

  /// 完成：优先将 b64 落到 [assetStore]，条目存 type:file。
  Future<void> completeItem(
    String sessionId,
    String itemId,
    List<ImageRef> images,
  ) async {
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
          final path = await _assetStore.savePng(
            bytes,
            '${itemId}_$i',
          );
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

  Future<void> _deleteItemAssets(List<ImageItem> items) async {
    for (final item in items) {
      for (final img in item.images) {
        if (img.type == ImageRefType.file && img.src.isNotEmpty) {
          try {
            await _assetStore.delete(img.src);
          } catch (_) {}
        }
      }
    }
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
