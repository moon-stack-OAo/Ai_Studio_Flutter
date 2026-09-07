import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../security/url_safety.dart';
import 'minisign_verify.dart';
import 'update_models.dart';
import 'update_platform.dart';
import 'version_compare.dart';

/// 拉取 / 解析清单并下载安装包。
class UpdateClient {
    UpdateClient({
    http.Client? client,
    this.manifestUrl = kDesktopUpdateManifestUrl,
    this.timeout = const Duration(seconds: 30),
    this.downloadDirectory,
    this.minisignPubkey = kDesktopUpdaterMinisignPubkey,
    this.requireSignature = true,
  })  : _ownedClient = client == null,
        _client = client ?? http.Client();

  /// 测试可注入下载目录；生产为 null 时用系统临时目录。
  final Directory? downloadDirectory;

  /// Tauri updater minisign 公钥（base64 编码的公钥文本）。
  ///
  /// 为空时若 [requireSignature] 为 true，下载后验签会失败阻断（失败安全）。
  final String minisignPubkey;

  /// 桌面安装包是否强制验签；默认 true。Android 侧载走 sha256，可关。
  final bool requireSignature;

  final http.Client _client;
  final bool _ownedClient;
  final String manifestUrl;
  final Duration timeout;

  bool get ownsClient => _ownedClient;

  bool get isConfigured => manifestUrl.trim().isNotEmpty;

  void close() {
    if (_ownedClient) {
      _client.close();
    }
  }

  /// 拉取并解析 Tauri 风格 latest.json。
  Future<UpdateManifest> fetchManifest({http.Client? client}) async {
    final url = manifestUrl.trim();
    if (url.isEmpty) {
      throw const UpdateException('未配置更新源');
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      throw UpdateException('更新源地址无效：$url');
    }
    try {
      assertSafeFetchUrl(uri);
    } on UrlSafetyException catch (e) {
      throw UpdateException(e.message);
    }

    final c = client ?? _client;
    late final http.Response response;
    try {
      response = await c.get(uri, headers: const {
        'Accept': 'application/json',
        'User-Agent': 'AiStudio-Flutter-Updater/1.0',
      }).timeout(timeout);
    } on SocketException catch (e) {
      throw UpdateException('网络不可用：${e.message}');
    } on HttpException catch (e) {
      throw UpdateException('HTTP 错误：${e.message}');
    } on FormatException catch (e) {
      throw UpdateException('请求失败：${e.message}');
    } catch (e) {
      throw UpdateException(_friendlyNetworkError(e));
    }

    if (response.statusCode == 404) {
      throw const UpdateException('暂无更新清单（404）');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw UpdateException('拉取清单失败：HTTP ${response.statusCode}');
    }

    final body = response.body.trim();
    if (body.isEmpty) {
      throw const UpdateException('更新清单为空');
    }

    late final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const UpdateException('更新清单不是合法 JSON');
    }

    if (decoded is! Map) {
      throw const UpdateException('更新清单格式无效');
    }
    final manifest = UpdateManifest.fromJson(Map<String, dynamic>.from(decoded));
    if (manifest.version.trim().isEmpty) {
      throw const UpdateException('更新清单缺少 version');
    }
    return manifest;
  }

  /// 检查更新：比较 [currentVersion] 与清单，并按 [platformCandidates] 选包。
  Future<UpdateCheckResult> checkForUpdate({
    required String currentVersion,
    List<String>? platformCandidates,
    http.Client? client,
  }) async {
    final current = normalizeVersion(currentVersion);
    if (!isConfigured) {
      return UpdateCheckResult.notConfigured(current);
    }

    try {
      final manifest = await fetchManifest(client: client);
      final candidates =
          platformCandidates ?? desktopUpdatePlatformCandidates();
      if (candidates.isEmpty) {
        return UpdateCheckResult.failed(
          currentVersion: current,
          message: '当前平台不支持桌面直链更新',
          manifest: manifest,
        );
      }

      final matchedKey = _firstMatchingKey(manifest, candidates);
      final asset = matchedKey == null
          ? null
          : manifest.platforms[matchedKey];

      if (!isRemoteNewer(manifest.version, current)) {
        return UpdateCheckResult.upToDate(
          currentVersion: current,
          manifest: manifest,
        );
      }

      if (matchedKey == null || asset == null || asset.url.isEmpty) {
        return UpdateCheckResult.noPlatformAsset(
          currentVersion: current,
          manifest: manifest,
        );
      }

      return UpdateCheckResult.available(
        currentVersion: current,
        manifest: manifest,
        asset: asset,
        matchedPlatformKey: matchedKey,
      );
    } on UpdateException catch (e) {
      return UpdateCheckResult.failed(
        currentVersion: current,
        message: e.message,
      );
    } catch (e) {
      return UpdateCheckResult.failed(
        currentVersion: current,
        message: _friendlyNetworkError(e),
      );
    }
  }

  String? _firstMatchingKey(
    UpdateManifest manifest,
    List<String> candidates,
  ) {
    for (final key in candidates) {
      final asset = manifest.platforms[key];
      if (asset != null && asset.url.isNotEmpty) return key;
    }
    return null;
  }

  /// 下载安装包到临时目录；[onProgress] 可选。
  ///
  /// 若 [requireSignature] 为 true，下载后按 [PlatformAsset.signature] 做
  /// minisign / Tauri 验签；失败删除文件并阻断安装。
  Future<File> downloadInstaller(
    PlatformAsset asset, {
    void Function(UpdateDownloadProgress progress)? onProgress,
    http.Client? client,
    String? fileNameHint,
  }) async {
    final url = asset.url.trim();
    if (url.isEmpty) {
      throw const UpdateException('安装包地址为空');
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      throw UpdateException('安装包地址无效：$url');
    }
    try {
      assertSafeFetchUrl(uri);
    } on UrlSafetyException catch (e) {
      throw UpdateException(e.message);
    }

    final c = client ?? _client;
    late final http.StreamedResponse response;
    try {
      final request = http.Request('GET', uri);
      request.headers['User-Agent'] = 'AiStudio-Flutter-Updater/1.0';
      response = await c.send(request).timeout(timeout);
    } catch (e) {
      throw UpdateException(_friendlyNetworkError(e));
    }

    if (response.statusCode == 403) {
      throw const UpdateException(
        '下载更新失败：安装包地址可能需要鉴权。请稍后重试，或到 GitHub Releases 手动下载安装。',
      );
    }
    if (response.statusCode == 404) {
      throw const UpdateException('下载更新失败：安装包不存在（404）');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw UpdateException('下载更新失败：HTTP ${response.statusCode}');
    }

    final total = response.contentLength;
    final dir = await _resolveDownloadDir();
    final name = _safeFileName(
      fileNameHint ?? uri.pathSegments.lastOrNull ?? 'update-installer',
    );
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(
          UpdateDownloadProgress(received: received, total: total),
        );
      }
      await sink.flush();
    } catch (e) {
      await sink.close();
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      throw UpdateException(_friendlyNetworkError(e));
    } finally {
      await sink.close();
    }

    if (received == 0) {
      try {
        await file.delete();
      } catch (_) {}
      throw const UpdateException('下载的安装包为空');
    }

    if (requireSignature) {
      try {
        final bytes = await file.readAsBytes();
        await verifyTauriUpdaterSignature(
          fileBytes: bytes,
          signatureField: asset.signature,
          pubkeyEncoded: minisignPubkey,
        );
      } catch (e) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
        if (e is UpdateException) rethrow;
        throw UpdateException('更新包签名校验失败：$e');
      }
    }
    return file;
  }

  Future<Directory> _resolveDownloadDir() async {
    final override = downloadDirectory;
    if (override != null) {
      if (!await override.exists()) {
        await override.create(recursive: true);
      }
      return override;
    }
    try {
      final temp = await getTemporaryDirectory();
      final dir = Directory(
        '${temp.path}${Platform.pathSeparator}ai_studio_update',
      );
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    } catch (_) {
      final dir = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}ai_studio_update',
      );
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    }
  }

  String _safeFileName(String raw) {
    var name = Uri.decodeComponent(raw).split(RegExp(r'[\\/]')).last.trim();
    if (name.isEmpty || name == '.' || name == '..') {
      name = 'update-installer';
    }
    name = name.replaceAll(RegExp(r'[^\w\-.\u4e00-\u9fff ]'), '_');
    if (!name.contains('.')) {
      name = '$name.bin';
    }
    return name;
  }

  String _friendlyNetworkError(Object err) {
    final msg = err.toString();
    final lower = msg.toLowerCase();
    if (lower.contains('timeout') || lower.contains('timed out')) {
      return '下载更新失败：请求超时，请检查网络后重试。';
    }
    if (lower.contains('socket') ||
        lower.contains('connection') ||
        lower.contains('network') ||
        lower.contains('failed host lookup') ||
        lower.contains('dns')) {
      return '下载更新失败：网络不稳定或无法访问更新源。请检查网络后重试。';
    }
    return '更新失败：$msg';
  }
}

/// 更新相关业务异常。
class UpdateException implements Exception {
  const UpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

extension _LastOrNull<E> on List<E> {
  E? get lastOrNull => isEmpty ? null : last;
}
