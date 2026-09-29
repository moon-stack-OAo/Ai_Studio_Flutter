import 'update_models.dart';
import 'update_platform.dart';

/// 将 AppDock `GET /public/apps/:slug/versions` 的 JSON 数组
/// 映射成内部 [UpdateManifest]（取非预发布最高版本）。
///
/// 相对 `downloadUrl` 会用 [baseUrl] 补成绝对地址。
/// 无法识别平台的资产会被跳过。
UpdateManifest updateManifestFromAppDockVersions(
  Object? decoded, {
  required String baseUrl,
}) {
  if (decoded is! List) {
    throw const FormatException('AppDock 版本列表不是数组');
  }
  final versions = <Map<String, dynamic>>[];
  for (final item in decoded) {
    if (item is Map<String, dynamic>) {
      versions.add(item);
    } else if (item is Map) {
      versions.add(Map<String, dynamic>.from(item));
    }
  }
  final latest = _pickLatestStable(versions);
  if (latest == null) {
    return const UpdateManifest(version: '0.0.0');
  }

  final tag = (latest['tagName'] ?? '').toString().trim();
  final platforms = <String, PlatformAsset>{};
  final rawAssets = latest['assets'];
  if (rawAssets is List) {
    for (final raw in rawAssets) {
      final asset = raw is Map<String, dynamic>
          ? raw
          : raw is Map
              ? Map<String, dynamic>.from(raw)
              : null;
      if (asset == null) continue;
      final name = (asset['name'] ?? '').toString();
      final keys = appDockAssetPlatformKeys(
        platform: (asset['platform'] ?? '').toString(),
        arch: (asset['arch'] ?? '').toString(),
        fileName: name,
      );
      if (keys.isEmpty) continue;
      final url = _absoluteDownloadUrl(
        baseUrl,
        (asset['downloadUrl'] ?? '').toString(),
      );
      if (url.isEmpty) continue;
      final mapped = PlatformAsset(
        url: url,
        sha256: (asset['checksumSha256'] ?? asset['sha256'] ?? '')
            .toString()
            .trim(),
        size: _asInt(asset['size']),
      );
      for (final key in keys) {
        platforms.putIfAbsent(key, () => mapped);
      }
    }
  }

  final published = latest['publishedAt'];
  return UpdateManifest(
    version: _coreVersion(tag),
    notes: (latest['body'] ?? latest['name'] ?? '').toString(),
    pubDate: published == null ? '' : published.toString(),
    platforms: platforms,
    product: kAppDockAppSlug,
  );
}

Map<String, dynamic>? _pickLatestStable(List<Map<String, dynamic>> versions) {
  Map<String, dynamic>? best;
  for (final version in versions) {
    if (version['isPrerelease'] == true) continue;
    final tag = (version['tagName'] ?? '').toString();
    if (tag.trim().isEmpty) continue;
    if (best == null ||
        _compareCore(tag, (best['tagName'] ?? '').toString()) > 0) {
      best = version;
    }
  }
  return best;
}

/// 只取 `v1.2.3` 的数字段，忽略 `+build` 与 `-prerelease`。
String _coreVersion(String raw) {
  final stripped =
      raw.trim().replaceFirst(RegExp(r'^v', caseSensitive: false), '');
  if (stripped.isEmpty) return '0.0.0';
  return stripped.split(RegExp(r'[+\-]')).first.trim();
}

int _compareCore(String a, String b) {
  final pa = _coreVersion(a).split('.');
  final pb = _coreVersion(b).split('.');
  final n = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < n; i++) {
    final x = i < pa.length ? int.tryParse(pa[i]) ?? 0 : 0;
    final y = i < pb.length ? int.tryParse(pb[i]) ?? 0 : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

String _absoluteDownloadUrl(String baseUrl, String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '';
  final parsed = Uri.tryParse(value);
  if (parsed != null && parsed.hasScheme) return value;
  final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  if (base.isEmpty) return value;
  if (value.startsWith('/')) return '$base$value';
  return '$base/$value';
}

int? _asInt(Object? raw) {
  if (raw is num) return raw.toInt();
  if (raw == null) return null;
  return int.tryParse(raw.toString());
}