import 'dart:io';

import 'package:http/http.dart' as http;

import 'sha256_util.dart';
import 'update_client.dart';
import 'update_installer.dart';
import 'update_models.dart';
import 'update_platform.dart';

/// Android 侧载更新客户端：检查 + 下载 + **sha256 校验**。
///
/// 复用 [UpdateClient] 的清单拉取与下载；默认清单为 [kAndroidUpdateManifestUrl]。
/// 安装由 [AndroidApkInstaller] 完成（勿使用 [DesktopUpdateInstaller]）。
class AndroidUpdateClient {
  AndroidUpdateClient({
    http.Client? client,
    this.manifestUrl = kAndroidUpdateManifestUrl,
    this.timeout = const Duration(seconds: 30),
    this.downloadDirectory,
    UpdateClient? updateClient,
  }) : _client = updateClient ??
            UpdateClient(
              client: client,
              manifestUrl: manifestUrl,
              timeout: timeout,
              downloadDirectory: downloadDirectory,
              // Android 侧载用 sha256，不走桌面 minisign。
              requireSignature: false,
            ),
        _ownsInner = updateClient == null;

  final UpdateClient _client;
  final bool _ownsInner;
  final String manifestUrl;
  final Duration timeout;
  final Directory? downloadDirectory;

  UpdateClient get updateClient => _client;

  bool get isConfigured => _client.isConfigured;

  void close() {
    if (_ownsInner) _client.close();
  }

  /// 检查更新；平台键默认 [androidUpdatePlatformCandidates]。
  ///
  /// 有更新时要求匹配资产含合法 `sha256`，否则返回 failed。
  Future<UpdateCheckResult> checkForUpdate({
    required String currentVersion,
    List<String>? platformCandidates,
    http.Client? client,
  }) async {
    final candidates =
        platformCandidates ?? androidUpdatePlatformCandidates();
    final result = await _client.checkForUpdate(
      currentVersion: currentVersion,
      platformCandidates: candidates,
      client: client,
    );
    if (!result.hasUpdate) return result;

    final asset = result.asset;
    if (asset == null || asset.url.isEmpty) {
      return UpdateCheckResult.noPlatformAsset(
        currentVersion: result.currentVersion,
        manifest: result.manifest!,
      );
    }
    if (!isValidSha256(asset.sha256)) {
      return UpdateCheckResult.failed(
        currentVersion: result.currentVersion,
        message: '更新清单缺少完整性校验信息',
        manifest: result.manifest,
      );
    }
    return result;
  }

  /// 下载 APK 并校验 sha256；失败删除临时文件。
  Future<File> downloadAndVerify(
    PlatformAsset asset, {
    void Function(UpdateDownloadProgress progress)? onProgress,
    http.Client? client,
    String? fileNameHint,
  }) async {
    final expected = requireValidSha256(asset.sha256);
    final file = await _client.downloadInstaller(
      asset,
      onProgress: onProgress,
      client: client,
      fileNameHint: fileNameHint ?? _apkNameHint(asset.url),
    );
    try {
      await verifyFileSha256(file, expected);
    } catch (e) {
      rethrow;
    }
    return file;
  }

  /// 下载校验后调起 [installer]。
  Future<File> downloadVerifyAndInstall(
    PlatformAsset asset,
    AndroidApkInstaller installer, {
    void Function(UpdateDownloadProgress progress)? onProgress,
    http.Client? client,
    String? fileNameHint,
  }) async {
    final file = await downloadAndVerify(
      asset,
      onProgress: onProgress,
      client: client,
      fileNameHint: fileNameHint,
    );
    await installer.install(file);
    return file;
  }

  String _apkNameHint(String url) {
    final uri = Uri.tryParse(url);
    final last = uri?.pathSegments.isNotEmpty == true
        ? uri!.pathSegments.last
        : '';
    if (last.toLowerCase().endsWith('.apk')) return last;
    return 'ai-studio-update.apk';
  }
}
