import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// 生视频队列封面（抽帧 JPEG）落盘抽象。
abstract class VideoPosterStore {
  /// 若已有缓存，返回本地路径；否则 `null`。
  Future<String?> pathFor(String itemId);

  /// 保存 JPEG 字节，返回本地路径。
  Future<String> saveJpeg(Uint8List bytes, String itemId);

  Future<void> delete(String itemId);

  /// 清空全部封面缓存（幂等）。
  Future<void> clearAll();

  /// 估算缓存占用字节。
  Future<int> estimateBytes();
}

/// 内存实现：路径形如 `memory-poster://{id}`。
class MemoryVideoPosterStore implements VideoPosterStore {
  final Map<String, Uint8List> _map = {};

  Map<String, Uint8List> get entries => Map.unmodifiable(_map);

  String _key(String id) => 'memory-poster://$id';

  @override
  Future<String?> pathFor(String itemId) async {
    final key = _key(itemId);
    return _map.containsKey(key) ? key : null;
  }

  @override
  Future<String> saveJpeg(Uint8List bytes, String itemId) async {
    final key = _key(itemId);
    _map[key] = Uint8List.fromList(bytes);
    return key;
  }

  @override
  Future<void> delete(String itemId) async {
    _map.remove(_key(itemId));
  }

  @override
  Future<void> clearAll() async {
    _map.clear();
  }

  @override
  Future<int> estimateBytes() async {
    var total = 0;
    for (final bytes in _map.values) {
      total += bytes.length;
    }
    return total;
  }
}

/// 桌面/移动：落到应用文档目录 `video_poster_cache/{id}.jpg`。
class FileVideoPosterStore implements VideoPosterStore {
  FileVideoPosterStore({this.overrideDir});

  final Directory? overrideDir;
  Directory? _cacheDir;

  Future<Directory> _ensureDir() async {
    final cached = _cacheDir;
    if (cached != null) return cached;
    final Directory dir;
    final override = overrideDir;
    if (override != null) {
      dir = override;
    } else {
      final docs = await getApplicationDocumentsDirectory();
      dir = Directory('${docs.path}${Platform.pathSeparator}video_poster_cache');
    }
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return _cacheDir = dir;
  }

  String _safeId(String id) {
    return id.replaceAll(RegExp(r'[^\w\-.]'), '_');
  }

  Future<File> _fileFor(String id) async {
    final dir = await _ensureDir();
    final name = _safeId(id);
    final withExt = name.endsWith('.jpg') || name.endsWith('.jpeg')
        ? name
        : '$name.jpg';
    return File('${dir.path}${Platform.pathSeparator}$withExt');
  }

  @override
  Future<String?> pathFor(String itemId) async {
    final file = await _fileFor(itemId);
    if (await file.exists()) return file.path;
    return null;
  }

  @override
  Future<String> saveJpeg(Uint8List bytes, String itemId) async {
    final file = await _fileFor(itemId);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  @override
  Future<void> delete(String itemId) async {
    final file = await _fileFor(itemId);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<void> clearAll() async {
    final dir = await _ensureDir();
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      try {
        await entity.delete(recursive: true);
      } catch (_) {}
    }
  }

  @override
  Future<int> estimateBytes() async {
    final dir = await _ensureDir();
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {}
      }
    }
    return total;
  }
}
