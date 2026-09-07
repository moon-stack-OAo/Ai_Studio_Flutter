import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'image_asset_store.dart';

/// 桌面/移动：落到应用文档目录 `image_cache/{id}.png`。
class FileImageAssetStore implements ImageAssetStore {
  FileImageAssetStore({this.overrideDir});

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
      dir = Directory('${docs.path}${Platform.pathSeparator}image_cache');
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
    final withExt = name.endsWith('.png') ? name : '$name.png';
    return File('${dir.path}${Platform.pathSeparator}$withExt');
  }

  @override
  Future<String> savePng(Uint8List bytes, String id) async {
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
    // 兼容仅传 id
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
