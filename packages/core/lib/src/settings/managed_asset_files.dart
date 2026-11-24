import 'dart:io';

/// Deletion is restricted to ordinary files below a trusted cache directory.
/// Reads intentionally retain their existing explicit external-file semantics.
class ManagedAssetFiles {
  ManagedAssetFiles(this.root);
  final Directory root;

  String _key(String path) {
    final normalized = File(path).absolute.uri.normalizePath().toFilePath();
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  Future<bool> _ordinaryPath(String path) async {
    var current = File(path).absolute.path;
    while (true) {
      final type = await FileSystemEntity.type(current, followLinks: false);
      if (type == FileSystemEntityType.link ||
          type == FileSystemEntityType.notFound) {
        return false;
      }
      final parent = File(current).parent.path;
      if (parent == current) return true;
      current = parent;
    }
  }

  Future<bool> containsFile(String path) async {
    // Reject traversal, including an alias that happens to normalize inside.
    if (path.split(RegExp(r'[/\\]')).contains('..')) return false;
    final base = _key(root.path);
    final target = _key(path);
    if (!target.startsWith('$base${Platform.pathSeparator}')) return false;
    return await _ordinaryPath(path) &&
        await FileSystemEntity.type(path, followLinks: false) ==
            FileSystemEntityType.file;
  }

  Future<void> delete(String path) async {
    if (await containsFile(path)) await File(path).delete();
  }

  Future<void> clearExcept(Set<String> retained) async {
    if (!await _ordinaryPath(root.path)) return;
    final keys = retained.map(_key).toSet();
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File && !keys.contains(_key(entity.path))) {
        await delete(entity.path);
      }
    }
  }
}
