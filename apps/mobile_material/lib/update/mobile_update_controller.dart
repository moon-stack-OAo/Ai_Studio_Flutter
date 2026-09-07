import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../platform/open_file_apk_installer.dart';

/// 移动端更新控制器。
///
/// - **Android**：检查 `android-latest.json` → 下载 + sha256 → [AndroidApkInstaller]
/// - **iOS**：不走 APK；检查仅用于展示「请通过内测渠道获取」说明
class MobileUpdateController extends ChangeNotifier {
  MobileUpdateController({
    AndroidUpdateClient? androidClient,
    AndroidApkInstaller? apkInstaller,
    String? currentVersion,
    List<String>? platformCandidates,
    this.forceIos = false,
    this.forceAndroid = false,
  })  : _androidClient = androidClient ??
            AndroidUpdateClient(manifestUrl: kAndroidUpdateManifestUrl),
        _apkInstaller = apkInstaller ?? const OpenFileAndroidApkInstaller(),
        _injectedVersion = currentVersion,
        _platformCandidates =
            platformCandidates ?? androidUpdatePlatformCandidates();

  final AndroidUpdateClient _androidClient;
  final AndroidApkInstaller _apkInstaller;
  final String? _injectedVersion;
  final List<String> _platformCandidates;

  /// 测试注入平台。
  final bool forceIos;
  final bool forceAndroid;

  String _currentVersion = '0.0.0';
  bool _versionReady = false;
  UpdateCheckResult? _lastCheck;
  bool _checking = false;
  bool _downloading = false;
  UpdateDownloadProgress? _downloadProgress;
  String? _lastError;
  File? _downloadedFile;

  String get currentVersion => _currentVersion;
  bool get isVersionReady => _versionReady;
  UpdateCheckResult? get lastCheck => _lastCheck;
  bool get isChecking => _checking;
  bool get isDownloading => _downloading;
  UpdateDownloadProgress? get downloadProgress => _downloadProgress;
  String? get lastError => _lastError;
  File? get downloadedFile => _downloadedFile;
  bool get hasUpdate => _lastCheck?.hasUpdate ?? false;

  bool get isIos {
    if (forceIos) return true;
    if (forceAndroid) return false;
    if (kIsWeb) return false;
    try {
      return Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  bool get isAndroid {
    if (forceAndroid) return true;
    if (forceIos) return false;
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  /// iOS 非 Store 说明文案。
  static const String iosNonStoreMessage =
      '请通过内测渠道获取新版本（非 App Store）';

  Future<void> ensureCurrentVersion() async {
    if (_versionReady && _injectedVersion == null) return;
    final injected = _injectedVersion;
    if (injected != null && injected.trim().isNotEmpty) {
      _currentVersion = normalizeVersion(injected);
      _versionReady = true;
      notifyListeners();
      return;
    }
    try {
      final info = await PackageInfo.fromPlatform();
      _currentVersion = normalizeVersion(info.version);
    } catch (_) {
      _currentVersion = '0.0.0';
    }
    _versionReady = true;
    notifyListeners();
  }

  /// 检查更新。iOS 不拉 APK 清单安装，仅返回说明性结果。
  Future<UpdateCheckResult> checkForUpdate() async {
    if (_checking) {
      return _lastCheck ??
          UpdateCheckResult.failed(
            currentVersion: _currentVersion,
            message: '正在检查更新',
          );
    }
    _checking = true;
    _lastError = null;
    notifyListeners();

    try {
      await ensureCurrentVersion();

      if (isIos) {
        // iOS：可尝试拉清单比对版本，但不提供 APK 安装路径。
        if (!_androidClient.isConfigured) {
          final result = UpdateCheckResult.failed(
            currentVersion: _currentVersion,
            message: iosNonStoreMessage,
          );
          _lastCheck = result;
          _lastError = iosNonStoreMessage;
          return result;
        }
        final result = await _androidClient.checkForUpdate(
          currentVersion: _currentVersion,
          platformCandidates: _platformCandidates,
        );
        // 有更新也只提示内测渠道，清空可安装 asset 语义由 UI 处理。
        if (result.hasUpdate) {
          final noted = UpdateCheckResult(
            status: UpdateCheckStatus.available,
            currentVersion: result.currentVersion,
            manifest: result.manifest,
            asset: null,
            matchedPlatformKey: result.matchedPlatformKey,
            errorMessage: iosNonStoreMessage,
          );
          _lastCheck = noted;
          return noted;
        }
        if (result.status == UpdateCheckStatus.upToDate) {
          _lastCheck = result;
          return result;
        }
        // 网络失败等：仍给出非 Store 说明
        final fallback = UpdateCheckResult.failed(
          currentVersion: _currentVersion,
          message: iosNonStoreMessage,
          manifest: result.manifest,
        );
        _lastCheck = fallback;
        _lastError = iosNonStoreMessage;
        return fallback;
      }

      if (!isAndroid) {
        final result = UpdateCheckResult.failed(
          currentVersion: _currentVersion,
          message: '当前平台不支持应用内更新',
        );
        _lastCheck = result;
        _lastError = result.errorMessage;
        return result;
      }

      final result = await _androidClient.checkForUpdate(
        currentVersion: _currentVersion,
        platformCandidates: _platformCandidates,
      );
      _lastCheck = result;
      if (result.status == UpdateCheckStatus.failed) {
        _lastError = result.errorMessage;
      }
      return result;
    } catch (e) {
      final result = UpdateCheckResult.failed(
        currentVersion: _currentVersion,
        message: e is UpdateException ? e.message : e.toString(),
      );
      _lastCheck = result;
      _lastError = result.errorMessage;
      return result;
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  /// Android：下载 + sha256 + 调起安装。iOS 直接失败。
  Future<bool> downloadAndInstall({UpdateCheckResult? result}) async {
    if (isIos) {
      _lastError = iosNonStoreMessage;
      notifyListeners();
      return false;
    }
    if (!isAndroid) {
      _lastError = '当前平台不支持 APK 安装';
      notifyListeners();
      return false;
    }
    final check = result ?? _lastCheck;
    if (check == null || !check.hasUpdate || check.asset == null) {
      _lastError = '没有可安装的更新';
      notifyListeners();
      return false;
    }
    if (_downloading) return false;

    _downloading = true;
    _downloadProgress = null;
    _lastError = null;
    notifyListeners();

    try {
      final file = await _androidClient.downloadVerifyAndInstall(
        check.asset!,
        _apkInstaller,
        onProgress: (p) {
          _downloadProgress = p;
          notifyListeners();
        },
      );
      _downloadedFile = file;
      return true;
    } on UpdateException catch (e) {
      _lastError = e.message;
      return false;
    } catch (e) {
      _lastError = e.toString();
      return false;
    } finally {
      _downloading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _androidClient.close();
    super.dispose();
  }
}
