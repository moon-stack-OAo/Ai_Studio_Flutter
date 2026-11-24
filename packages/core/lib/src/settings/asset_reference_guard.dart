import 'dart:io';

String assetReferenceKey(String value) {
  if (value.contains('://') || value.startsWith('data:')) return value;
  final path = File(value).absolute.uri.normalizePath().toFilePath();
  return Platform.isWindows ? path.toLowerCase() : path;
}

/// Current, readable repository references only; recovery-point policy is separate.
class AssetReferenceGuard {
  final Map<Object, Set<String> Function()> _sources = {};

  void register(Object owner, Set<String> Function() references) {
    _sources[owner] = references;
  }

  Set<String> retainedByOthers(Object owner) => {
    for (final entry in _sources.entries)
      if (!identical(entry.key, owner)) ...entry.value().map(assetReferenceKey),
  };
}

/// Optional capability: existing third-party/fake stores need not implement it.
abstract interface class SelectiveAssetClear {
  Future<void> clearExcept(Set<String> retained);
}
