import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../security/safe_http_client.dart';
import '../security/url_safety.dart';
import 'appdock_access.dart';
import 'appdock_manifest.dart';
import 'minisign_verify.dart';
import 'sha256_util.dart';
import 'update_models.dart';
import 'update_platform.dart';
import 'version_compare.dart';

/// 下载/安装瞬时网络失败时的最大尝试次数（含首次）。
const kUpdateInstallMaxAttempts = 3;

/// 拉取 / 解析清单并下载安装包。
class UpdateClient {
  UpdateClient({
    http.Client? client,
    this.manifestUrl = kDesktopUpdateManifestUrl,
    this.fallbackManifestUrl = kGithubDesktopUpdateManifestUrl,
    this.timeout = const Duration(seconds: 45),
    this.downloadDirectory,
    this.minisignPubkey = kDesktopUpdaterMinisignPubkey,
    this.requireSignature = true,
    this.installMaxAttempts = kUpdateInstallMaxAttempts,
    this.accessSession,
  })  : _ownedClient = client == null,
        _client = client ?? createSafeHttpClient();

  /// 测试可注入下载目录；生产为 null 时用系统临时目录。
  final Directory? downloadDirectory;

  /// Tauri updater minisign 公钥（base64 编码的公钥文本）。
  ///
  /// 为空时若 [requireSignature] 为 true，下载后验签会失败阻断（失败安全）。
  final String minisignPubkey;

  /// 桌面安装包是否强制验签；默认 true。Android 侧载走 sha256，可关。
  final bool requireSignature;

  /// 下载瞬时失败时的最大尝试次数（含首次）；签名/格式错误不重试。
  final int installMaxAttempts;

  /// AppDock 访问口令会话；有值时清单与下载请求带 cookie。
  final AppDockAccessSession? accessSession;

  final http.Client _client;
  final bool _ownedClient;
  final String manifestUrl;

  /// AppDock 没有该应用（404 / 网络失败）时改拉的 GitHub 清单。空则不回退。
  ///
  /// 需要访问口令时不回退，避免绕过 AppDock。
  final String fallbackManifestUrl;
  final Duration timeout;

  bool get ownsClient => _ownedClient;

  bool get isConfigured => manifestUrl.trim().isNotEmpty;

  void close() {
    if (_ownedClient) {
      _client.close();
    }
  }

  /// 拉取并解析更新清单。
  ///
  /// AppDock 版本列表（JSON 数组）会映射成内部清单；
  /// 旧 Tauri `latest.json`（JSON 对象）仍可解析，供测试与兼容。
  ///
  /// [manifestUrl] 为 404 或网络失败、且配置了 [fallbackManifestUrl] 时，
  /// 再拉 GitHub 清单。需要访问口令时不回退。
  Future<UpdateManifest> fetchManifest({http.Client? client}) async {
    final url = manifestUrl.trim();
    if (url.isEmpty) {
      throw const UpdateException('未配置更新源');
    }
    try {
      return await _fetchManifestAt(url, client: client);
    } on UpdateException catch (e) {
      final fallback = fallbackManifestUrl.trim();
      if (fallback.isEmpty ||
          fallback == url ||
          !_canFallbackToGithub(e)) {
        rethrow;
      }
      return _fetchManifestAt(fallback, client: client);
    }
  }

  /// 仅「没有这个应用 / 源暂时打不开」才回退；口令不足必须停在 AppDock。
  bool _canFallbackToGithub(UpdateException error) {
    final msg = error.message;
    if (msg == kUpdateAccessRequiredMessage || msg.contains('访问口令')) {
      return false;
    }
    return msg.contains('404') ||
        msg.contains('更新清单为空') ||
        msg.contains('无法访问更新源') ||
        msg.contains('请求超时') ||
        msg.contains('网络');
  }

  Future<UpdateManifest> _fetchManifestAt(
    String url, {
    http.Client? client,
  }) async {
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
      response = await c
          .get(uri, headers: _requestHeaders(json: true))
          .timeout(timeout);
    } on TimeoutException {
      throw const UpdateException(
        '检查更新失败：请求超时，请检查网络后重试。',
      );
    } on SocketException catch (e) {
      throw UpdateException(friendlyUpdateNetworkError(e));
    } on HttpException catch (e) {
      throw UpdateException('HTTP 错误：${e.message}');
    } on FormatException catch (e) {
      throw UpdateException('请求失败：${e.message}');
    } catch (e) {
      throw UpdateException(friendlyUpdateNetworkError(e));
    }

    if (updateResponseNeedsAccess(response.statusCode, response.bodyBytes)) {
      throw const UpdateException(kUpdateAccessRequiredMessage);
    }
    if (response.statusCode == 404) {
      throw const UpdateException('暂无更新清单（404）');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw UpdateException('拉取清单失败：HTTP ${response.statusCode}');
    }

    // GitHub release 资产常为 application/octet-stream（无 charset）；
    // 勿用 response.body（缺 charset 时按 latin1 解，中文会乱码）。
    late final String body;
    try {
      body = utf8.decode(response.bodyBytes).trim();
    } on FormatException {
      throw const UpdateException('更新清单不是合法 UTF-8');
    }
    if (body.isEmpty) {
      throw const UpdateException('更新清单为空');
    }

    late final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const UpdateException('更新清单不是合法 JSON');
    }

    final UpdateManifest manifest;
    if (decoded is List) {
      try {
        manifest = updateManifestFromAppDockVersions(
          decoded,
          baseUrl: _manifestOrigin(url),
        );
      } on FormatException catch (e) {
        throw UpdateException(e.message);
      }
    } else if (decoded is Map) {
      manifest = UpdateManifest.fromJson(Map<String, dynamic>.from(decoded));
    } else {
      throw const UpdateException('更新清单格式无效');
    }
    if (manifest.version.trim().isEmpty) {
      throw const UpdateException('更新清单缺少 version');
    }
    return manifest;
  }

  /// 清单 URL 的 scheme + host（含端口），用来补全 AppDock 相对下载路径。
  String _manifestOrigin(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return '';
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port';
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

      if (!isValidSha256(asset.sha256) &&
          (!requireSignature || asset.signature.trim().isEmpty)) {
        return UpdateCheckResult.failed(
          currentVersion: current,
          message: '更新清单缺少完整性校验信息',
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
        message: friendlyUpdateNetworkError(e),
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
  /// 有合法 `sha256` 时下载后做完整性校验（AppDock）。
  /// 否则若 [requireSignature] 为 true，按 [PlatformAsset.signature] 做
  /// minisign / Tauri 验签。失败删除文件并阻断安装。
  ///
  /// 瞬时网络失败会自动重试（最多 [installMaxAttempts] 次）；签名/格式类错误不重试。
  Future<File> downloadInstaller(
    PlatformAsset asset, {
    void Function(UpdateDownloadProgress progress)? onProgress,
    void Function(int attempt, int maxAttempts)? onRetry,
    bool Function()? shouldCancel,
    http.Client? client,
    String? fileNameHint,
  }) async {
    final maxAttempts =
        installMaxAttempts < 1 ? 1 : installMaxAttempts;
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      _throwIfDownloadCancelled(shouldCancel);
      try {
        return await _downloadInstallerOnce(
          asset,
          onProgress: onProgress,
          shouldCancel: shouldCancel,
          client: client,
          fileNameHint: fileNameHint,
        );
      } catch (e) {
        lastError = e;
        if (isUpdateDownloadCancelled(e)) {
          if (e is UpdateException) rethrow;
          throw const UpdateException(kUpdateDownloadCancelledMessage);
        }
        final retryable = isRetryableUpdateInstallError(e);
        if (!retryable || attempt >= maxAttempts) {
          if (e is UpdateException) rethrow;
          throw UpdateException(friendlyUpdateInstallError(e));
        }
        onRetry?.call(attempt, maxAttempts);
        await Future<void>.delayed(Duration(milliseconds: 600 * attempt));
      }
    }
    throw UpdateException(friendlyUpdateInstallError(lastError ?? '下载失败'));
  }

  Future<File> _downloadInstallerOnce(
    PlatformAsset asset, {
    void Function(UpdateDownloadProgress progress)? onProgress,
    bool Function()? shouldCancel,
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
      request.headers.addAll(_requestHeaders());
      response = await c.send(request).timeout(timeout);
    } on TimeoutException {
      throw const UpdateException(
        '下载更新失败：请求超时，请检查网络后重试。',
      );
    } catch (e) {
      throw UpdateException(friendlyUpdateNetworkError(e));
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      final sniffed = await _sniffAccessBody(response);
      if (sniffed) {
        throw const UpdateException(kUpdateAccessRequiredMessage);
      }
      throw const UpdateException(
        '下载更新失败：安装包地址可能需要鉴权。请确认 AppDock 应用为公开，或稍后重试。',
      );
    }
    if (response.statusCode == 404) {
      throw const UpdateException('下载更新失败：安装包不存在（404）');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw UpdateException('下载更新失败：HTTP ${response.statusCode}');
    }

    _throwIfDownloadCancelled(shouldCancel);

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
        _throwIfDownloadCancelled(shouldCancel);
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(
          UpdateDownloadProgress(received: received, total: total),
        );
      }
      await sink.flush();
      _throwIfDownloadCancelled(shouldCancel);
    } on UpdateException {
      await sink.close();
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      rethrow;
    } catch (e) {
      await sink.close();
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      if (isUpdateDownloadCancelled(e)) {
        throw const UpdateException(kUpdateDownloadCancelledMessage);
      }
      throw UpdateException(friendlyUpdateNetworkError(e));
    } finally {
      await sink.close();
    }

    if (received == 0) {
      try {
        await file.delete();
      } catch (_) {}
      throw const UpdateException('下载的安装包为空');
    }

    if (isValidSha256(asset.sha256)) {
      try {
        await verifyFileSha256(file, asset.sha256);
      } catch (e) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
        if (e is UpdateException) rethrow;
        throw UpdateException(friendlyUpdateInstallError(e));
      }
    } else if (requireSignature) {
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
        throw UpdateException(friendlyUpdateInstallError(e));
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

  Map<String, String> _requestHeaders({bool json = false}) {
    return {
      'User-Agent': 'AiStudio-Flutter-Updater/1.0',
      if (json) 'Accept': 'application/json',
      ...?accessSession?.headers,
    };
  }

  /// 读少量响应体判断是否口令不足，并尽量排空流。
  Future<bool> _sniffAccessBody(http.StreamedResponse response) async {
    final chunks = <int>[];
    try {
      await for (final chunk in response.stream) {
        if (chunks.length < 2048) {
          final room = 2048 - chunks.length;
          chunks.addAll(chunk.length <= room ? chunk : chunk.take(room));
        }
      }
    } catch (_) {}
    return updateResponseNeedsAccess(response.statusCode, chunks);
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

}

/// 将检查/下载阶段的网络原始错误转成可读中文。
String friendlyUpdateNetworkError(Object? err) {
  final msg = _errorText(err);
  final lower = msg.toLowerCase();

  if (_looksLikeTimeout(msg, lower)) {
    return '检查更新失败：请求超时，请检查网络后重试。';
  }
  if (RegExp(
        r'api\.github\.com/.*/releases/assets/',
        caseSensitive: false,
      ).hasMatch(msg) ||
      msg.contains(kUpdateAccessRequiredMessage)) {
    return kUpdateAccessRequiredMessage;
  }
  if (RegExp(r'\b403\b').hasMatch(msg) || lower.contains('forbidden')) {
    return '下载更新失败：安装包地址可能需要鉴权。请确认 AppDock 应用为公开，或稍后重试。';
  }
  if (lower.contains('socket') ||
      lower.contains('connection') ||
      lower.contains('network') ||
      lower.contains('failed host lookup') ||
      lower.contains('dns') ||
      lower.contains('failed to fetch') ||
      msg.contains('网络') ||
      msg.contains('连接')) {
    return '检查更新失败：网络不稳定或无法访问更新源。请检查网络后重试。';
  }
  if (msg.isEmpty) return '检查更新失败';
  return '检查更新失败：$msg';
}

/// 用户主动取消下载时的固定文案。
const kUpdateDownloadCancelledMessage = '已取消下载';

void _throwIfDownloadCancelled(bool Function()? shouldCancel) {
  if (shouldCancel?.call() == true) {
    throw const UpdateException(kUpdateDownloadCancelledMessage);
  }
}

/// 是否为用户取消下载。
bool isUpdateDownloadCancelled(Object? err) {
  final msg = _errorText(err);
  return msg.contains(kUpdateDownloadCancelledMessage) || msg.contains('已取消');
}

/// 将下载/安装错误转成可读中文（对齐旧版 updater 文案）。
String friendlyUpdateInstallError(Object? err) {
  final msg = _errorText(err);
  final lower = msg.toLowerCase();

  if (isUpdateDownloadCancelled(err)) {
    return kUpdateDownloadCancelledMessage;
  }

  if (RegExp(
        r'api\.github\.com/.*/releases/assets/',
        caseSensitive: false,
      ).hasMatch(msg) ||
      msg.contains(kUpdateAccessRequiredMessage)) {
    return kUpdateAccessRequiredMessage;
  }
  if (RegExp(r'\b403\b').hasMatch(msg) || lower.contains('forbidden')) {
    return '下载更新失败：安装包地址可能需要鉴权。请确认 AppDock 应用为公开，或稍后重试。';
  }
  if (_looksLikeTimeout(msg, lower) ||
      lower.contains('connection') ||
      lower.contains('network') ||
      lower.contains('dns') ||
      lower.contains('failed to fetch') ||
      lower.contains('error sending request') ||
      msg.contains('网络') ||
      msg.contains('连接')) {
    return '下载更新失败：网络不稳定或无法访问更新源。请检查网络后重试。';
  }
  if (lower.contains('signature') ||
      lower.contains('minisign') ||
      lower.contains('verify') ||
      msg.contains('签名')) {
    return '更新包签名校验失败，请稍后重试或手动下载安装。';
  }
  if (lower.contains('invalid updater') ||
      lower.contains('binary not found') ||
      lower.contains('extract') ||
      lower.contains('sha256')) {
    return '更新包格式或完整性校验失败，请稍后重试或手动下载安装。';
  }
  return msg.isEmpty ? '安装更新失败' : msg;
}

/// 瞬时网络类错误可重试；签名/格式/鉴权类不重试。
bool isRetryableUpdateInstallError(Object? err) {
  final msg = _errorText(err);
  final lower = msg.toLowerCase();
  if (msg.isEmpty) return true;
  if (isUpdateDownloadCancelled(err)) return false;
  if (lower.contains('signature') ||
      lower.contains('minisign') ||
      lower.contains('verify') ||
      lower.contains('invalid updater') ||
      lower.contains('binary not found') ||
      lower.contains('unsupported') ||
      lower.contains('sha256') ||
      msg.contains('签名') ||
      msg.contains('完整性') ||
      msg.contains('鉴权') ||
      RegExp(r'\b403\b').hasMatch(msg) ||
      RegExp(r'\b404\b').hasMatch(msg)) {
    return false;
  }
  return _looksLikeTimeout(msg, lower) ||
      lower.contains('connection') ||
      lower.contains('network') ||
      lower.contains('dns') ||
      lower.contains('failed to fetch') ||
      lower.contains('error sending request') ||
      RegExp(r'\b502\b|\b503\b|\b504\b|\b429\b').hasMatch(msg) ||
      msg.contains('网络') ||
      msg.contains('连接') ||
      msg.contains('超时');
}

String _errorText(Object? err) {
  if (err == null) return '';
  if (err is UpdateException) return err.message;
  if (err is TimeoutException) {
    return err.message?.isNotEmpty == true ? err.message! : 'TimeoutException';
  }
  return err.toString();
}

bool _looksLikeTimeout(String msg, String lower) {
  return lower.contains('timeout') ||
      lower.contains('timed out') ||
      lower.contains('timeoutexception') ||
      msg.contains('信号灯') ||
      msg.contains('超时');
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
