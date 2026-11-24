import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../settings/asset_reference_guard.dart';
import '../settings/managed_asset_files.dart';

import 'image_asset_store.dart';

/// 桌面/移动：落到应用文档目录 `{subdir}/{id}.png`。
///
/// 默认 [subdir] 为 `image_cache`（生图）；对话附图用 `chat_image_cache`。
/// [overrideDir] 非空时忽略 [subdir]，直接使用该目录。
class FileImageAssetStore implements ImageAssetStore, SelectiveAssetClear {
  FileImageAssetStore({this.overrideDir, this.subdir = 'image_cache'});

  final Directory? overrideDir;

  /// 相对应用文档目录的子目录名（如 `image_cache` / `chat_image_cache`）。
  final String subdir;

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
      final name = subdir.trim().isEmpty ? 'image_cache' : subdir.trim();
      dir = Directory('${docs.path}${Platform.pathSeparator}$name');
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
    final files = ManagedAssetFiles(await _ensureDir());
    // Bare ids remain supported; paths must never be sanitized into another id.
    if (!pathOrId.contains(RegExp(r'[/\\:]')) &&
        pathOrId != '.' &&
        pathOrId != '..') {
      await files.delete((await _fileFor(pathOrId)).path);
    } else {
      await files.delete(pathOrId);
    }
  }

  @override
  Future<void> clearAll() => clearExcept({});

  @override
  Future<void> clearExcept(Set<String> retained) async {
    await ManagedAssetFiles(await _ensureDir()).clearExcept(retained);
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
