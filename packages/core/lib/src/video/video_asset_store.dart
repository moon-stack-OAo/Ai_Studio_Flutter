import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// 生视频二进制落盘抽象。
abstract class VideoAssetStore {
  /// 保存视频字节，返回本地路径或稳定 id。
  Future<String> saveMp4(Uint8List bytes, String id);

  Future<Uint8List?> read(String pathOrId);

  Future<void> delete(String pathOrId);

  /// 清空全部媒体缓存（幂等）。
  Future<void> clearAll();

  /// 估算缓存占用字节。
  Future<int> estimateBytes();
}

/// 内存实现：路径形如 `memory://{id}`。
class MemoryVideoAssetStore implements VideoAssetStore {
  final Map<String, Uint8List> _map = {};

  Map<String, Uint8List> get entries => Map.unmodifiable(_map);

  @override
  Future<String> saveMp4(Uint8List bytes, String id) async {
    final key = 'memory://$id';
    _map[key] = Uint8List.fromList(bytes);
    return key;
  }

  @override
  Future<Uint8List?> read(String pathOrId) async => _map[pathOrId];

  @override
  Future<void> delete(String pathOrId) async {
    _map.remove(pathOrId);
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

/// 桌面/移动：落到应用文档目录 `video_cache/{id}.mp4`。
class FileVideoAssetStore implements VideoAssetStore {
  FileVideoAssetStore({this.overrideDir});

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
      dir = Directory('${docs.path}${Platform.pathSeparator}video_cache');
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
    final withExt = name.endsWith('.mp4') ? name : '$name.mp4';
    return File('${dir.path}${Platform.pathSeparator}$withExt');
  }

  @override
  Future<String> saveMp4(Uint8List bytes, String id) async {
    final file = await _fileFor(id);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  @override
  Future<Uint8List?> read(String pathOrId) async {
    final file = File(pathOrId);
    if (await file.exists()) {
      return file.readAsBytes();
    }
    final byId = await _fileFor(pathOrId);
    if (await byId.exists()) {
      return byId.readAsBytes();
    }
    return null;
  }

  @override
  Future<void> delete(String pathOrId) async {
    final file = File(pathOrId);
    if (await file.exists()) {
      await file.delete();
      return;
    }
    final byId = await _fileFor(pathOrId);
    if (await byId.exists()) {
      await byId.delete();
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
