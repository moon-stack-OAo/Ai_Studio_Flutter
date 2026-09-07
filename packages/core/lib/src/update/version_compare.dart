/// 去掉前导 `v`、取 `+`/`-` 前核心段，返回可比较的数字部件。
///
/// 对齐现网 `normalizeVersion`。
String normalizeVersion(String? raw) {
  final s = (raw ?? '').trim().replaceFirst(RegExp(r'^v', caseSensitive: false), '');
  if (s.isEmpty) return '';
  return s.split(RegExp(r'[+\-]')).first.trim();
}

List<int> _parts(String normalized) {
  if (normalized.isEmpty) return const [0];
  return normalized.split('.').map((p) {
    final m = RegExp(r'^\d+').firstMatch(p);
    return m == null ? 0 : int.tryParse(m.group(0)!) ?? 0;
  }).toList();
}

/// 比较两个版本：`>0` 表示 [a] 更新，`<0` 表示 [b] 更新，`0` 相等。
///
/// 仅比较数字段（major.minor.patch…）；忽略 build metadata 与 prerelease 后缀。
int compareVersions(String? a, String? b) {
  final na = normalizeVersion(a);
  final nb = normalizeVersion(b);
  final pa = _parts(na);
  final pb = _parts(nb);
  final n = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < n; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

/// 远端版本是否严格大于本地版本。
bool isRemoteNewer(String? remote, String? local) =>
    compareVersions(remote, local) > 0;
