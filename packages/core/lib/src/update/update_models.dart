import 'version_compare.dart';

/// 默认桌面更新清单 URL（`latest.json`，平台键兼容历史 updater 格式）。
const String kDesktopUpdateManifestUrl =
    'https://github.com/moon-stack-OAo/Ai_Studio_Flutter/releases/latest/download/latest.json';

/// 默认 Android 侧载更新清单 URL。
///
/// 字段：`version` / `notes` / `pub_date` / `platforms`；
/// 平台资产除 `url` 外须含 **`sha256`**（64 位 hex）。
const String kAndroidUpdateManifestUrl =
    'https://github.com/moon-stack-OAo/Ai_Studio_Flutter/releases/latest/download/android-latest.json';

/// 单平台安装包条目。
class PlatformAsset {
  const PlatformAsset({
    required this.url,
    this.signature = '',
    this.sha256 = '',
    this.size,
  });

  final String url;

  /// minisign / Tauri updater 签名（桌面下载后校验；Android 侧载通常为空）。
  final String signature;

  /// Android APK 完整性校验（小写 hex）；桌面清单通常为空。
  final String sha256;

  /// 可选字节大小（Android 清单）。
  final int? size;

  factory PlatformAsset.fromJson(Map<String, dynamic> json) {
    final sizeRaw = json['size'];
    int? size;
    if (sizeRaw is num) {
      size = sizeRaw.toInt();
    } else if (sizeRaw != null) {
      size = int.tryParse(sizeRaw.toString());
    }
    return PlatformAsset(
      url: (json['url'] ?? '').toString().trim(),
      signature: (json['signature'] ?? '').toString(),
      sha256: (json['sha256'] ?? json['sha_256'] ?? '').toString().trim(),
      size: size,
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        if (signature.isNotEmpty) 'signature': signature,
        if (sha256.isNotEmpty) 'sha256': sha256,
        if (size != null) 'size': size,
      };
}

/// Tauri 风格 `latest.json` 清单。
class UpdateManifest {
  const UpdateManifest({
    required this.version,
    this.notes = '',
    this.pubDate = '',
    this.platforms = const {},
    this.product,
  });

  final String version;
  final String notes;
  final String pubDate;
  final Map<String, PlatformAsset> platforms;

  /// 可选产品标记；若存在且非本产品，安装前应拦截。
  final String? product;

  String get normalizedVersion => normalizeVersion(version);

  factory UpdateManifest.fromJson(Map<String, dynamic> json) {
    final rawPlatforms = json['platforms'];
    final platforms = <String, PlatformAsset>{};
    if (rawPlatforms is Map) {
      for (final entry in rawPlatforms.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value is Map<String, dynamic>) {
          platforms[key] = PlatformAsset.fromJson(value);
        } else if (value is Map) {
          platforms[key] = PlatformAsset.fromJson(
            Map<String, dynamic>.from(value),
          );
        }
      }
    }
    final productRaw = json['product']?.toString().trim();
    return UpdateManifest(
      version: (json['version'] ?? '').toString().trim(),
      notes: (json['notes'] ?? json['body'] ?? '').toString(),
      pubDate: (json['pub_date'] ?? json['date'] ?? '').toString(),
      platforms: platforms,
      product: (productRaw == null || productRaw.isEmpty) ? null : productRaw,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        if (notes.isNotEmpty) 'notes': notes,
        if (pubDate.isNotEmpty) 'pub_date': pubDate,
        if (product != null) 'product': product,
        'platforms': {
          for (final e in platforms.entries) e.key: e.value.toJson(),
        },
      };

  /// 按候选平台键顺序匹配；返回第一个有非空 url 的条目。
  PlatformAsset? resolvePlatform(Iterable<String> candidateKeys) {
    for (final key in candidateKeys) {
      final asset = platforms[key];
      if (asset != null && asset.url.isNotEmpty) return asset;
    }
    return null;
  }
}

/// 检查更新结果状态。
enum UpdateCheckStatus {
  /// 未配置清单 URL。
  notConfigured,

  /// 已是最新。
  upToDate,

  /// 有可用更新。
  available,

  /// 清单无本平台包。
  noPlatformAsset,

  /// 网络 / 解析 / HTTP 失败。
  failed,
}

/// 一次「检查更新」的结果。
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.status,
    required this.currentVersion,
    this.manifest,
    this.asset,
    this.matchedPlatformKey,
    this.errorMessage,
  });

  final UpdateCheckStatus status;
  final String currentVersion;
  final UpdateManifest? manifest;
  final PlatformAsset? asset;
  final String? matchedPlatformKey;
  final String? errorMessage;

  bool get hasUpdate => status == UpdateCheckStatus.available;

  String? get latestVersion => manifest?.normalizedVersion;

  String get notes => manifest?.notes ?? '';

  factory UpdateCheckResult.notConfigured(String currentVersion) {
    return UpdateCheckResult(
      status: UpdateCheckStatus.notConfigured,
      currentVersion: currentVersion,
      errorMessage: '未配置更新源',
    );
  }

  factory UpdateCheckResult.upToDate({
    required String currentVersion,
    required UpdateManifest manifest,
  }) {
    return UpdateCheckResult(
      status: UpdateCheckStatus.upToDate,
      currentVersion: currentVersion,
      manifest: manifest,
    );
  }

  factory UpdateCheckResult.available({
    required String currentVersion,
    required UpdateManifest manifest,
    required PlatformAsset asset,
    required String matchedPlatformKey,
  }) {
    return UpdateCheckResult(
      status: UpdateCheckStatus.available,
      currentVersion: currentVersion,
      manifest: manifest,
      asset: asset,
      matchedPlatformKey: matchedPlatformKey,
    );
  }

  factory UpdateCheckResult.noPlatformAsset({
    required String currentVersion,
    required UpdateManifest manifest,
  }) {
    return UpdateCheckResult(
      status: UpdateCheckStatus.noPlatformAsset,
      currentVersion: currentVersion,
      manifest: manifest,
      errorMessage: '清单中无当前平台的安装包',
    );
  }

  factory UpdateCheckResult.failed({
    required String currentVersion,
    required String message,
    UpdateManifest? manifest,
  }) {
    return UpdateCheckResult(
      status: UpdateCheckStatus.failed,
      currentVersion: currentVersion,
      manifest: manifest,
      errorMessage: message,
    );
  }
}

/// 下载进度（字节）。
class UpdateDownloadProgress {
  const UpdateDownloadProgress({
    required this.received,
    this.total,
  });

  final int received;
  final int? total;

  double? get fraction {
    final t = total;
    if (t == null || t <= 0) return null;
    return (received / t).clamp(0.0, 1.0);
  }
}
