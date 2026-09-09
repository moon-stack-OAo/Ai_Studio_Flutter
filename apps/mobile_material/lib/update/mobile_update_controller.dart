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
    AppLogRepository? appLogRepository,
    UpdatePrefs? updatePrefs,
    String? currentVersion,
    List<String>? platformCandidates,
    this.forceIos = false,
    this.forceAndroid = false,
  })  : _androidClient = androidClient ??
            AndroidUpdateClient(manifestUrl: kAndroidUpdateManifestUrl),
        _apkInstaller = apkInstaller ?? const OpenFileAndroidApkInstaller(),
        _appLogs = appLogRepository,
        _prefs = updatePrefs ?? UpdatePrefs(),
        _ownsPrefs = updatePrefs == null,
        _injectedVersion = currentVersion,
        _platformCandidates =
            platformCandidates ?? androidUpdatePlatformCandidates();

  final AndroidUpdateClient _androidClient;
  final AndroidApkInstaller _apkInstaller;
  final AppLogRepository? _appLogs;
  final UpdatePrefs _prefs;
  final bool _ownsPrefs;
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
  bool _cancelRequested = false;
  UpdateDownloadProgress? _downloadProgress;
  String? _progressLabel;
  String? _lastError;
  File? _downloadedFile;

  UpdatePrefs get prefs => _prefs;

  String get currentVersion => _currentVersion;
  bool get isVersionReady => _versionReady;
  UpdateCheckResult? get lastCheck => _lastCheck;
  bool get isChecking => _checking;
  bool get isDownloading => _downloading;
  bool get isCancelRequested => _cancelRequested;
  UpdateDownloadProgress? get downloadProgress => _downloadProgress;
  String? get progressLabel => _progressLabel;
  String? get lastError => _lastError;
  File? get downloadedFile => _downloadedFile;
  bool get hasUpdate => _lastCheck?.hasUpdate ?? false;
  bool get hasAvailableUpdate => _prefs.hasAvailableUpdate;
  bool get autoCheckUpdate => _prefs.autoCheckUpdate;

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

  Future<void> ensurePrefsLoaded() => _prefs.ensureLoaded();

  Future<void> setAutoCheckUpdate(bool value) async {
    await _prefs.setAutoCheckUpdate(value);
    notifyListeners();
  }

  Future<void> skipUpdateVersion(String? version) async {
    await _prefs.skipUpdateVersion(version);
    _lastCheck = null;
    _lastError = null;
    notifyListeners();
  }

  /// [silent]：启动静默检查；已跳过版本不写角标、不改关于页结果；失败只打 warn。
  /// 手动检查会清除 skipped，并始终更新 [lastCheck]。
  Future<UpdateCheckResult> checkForUpdate({bool silent = false}) async {
    if (_checking) {
      return _lastCheck ??
          UpdateCheckResult.failed(
            currentVersion: _currentVersion,
            message: '正在检查更新',
          );
    }
    _checking = true;
    _lastError = null;
    if (!silent) {
      _lastCheck = null;
      _downloadProgress = null;
      _progressLabel = null;
    }
    notifyListeners();

    try {
      await ensureCurrentVersion();
      await _prefs.ensureLoaded();

      if (isIos) {
        return await _checkIos(silent: silent);
      }

      if (!isAndroid) {
        final result = UpdateCheckResult.failed(
          currentVersion: _currentVersion,
          message: '当前平台不支持应用内更新',
        );
        if (!silent) {
          _lastCheck = result;
          _lastError = result.errorMessage;
        }
        return result;
      }

      if (!_androidClient.isConfigured) {
        final result = UpdateCheckResult.notConfigured(_currentVersion);
        if (!silent) {
          _lastCheck = result;
          await _log(AppLogLevel.warn, '检查更新：未配置更新源');
        }
        return result;
      }

      final result = await _androidClient.checkForUpdate(
        currentVersion: _currentVersion,
        platformCandidates: _platformCandidates,
      );
      return await _applyCheckResult(result, silent: silent);
    } catch (e) {
      final result = UpdateCheckResult.failed(
        currentVersion: _currentVersion,
        message: e is UpdateException ? e.message : e.toString(),
      );
      _lastError = result.errorMessage;
      if (silent) {
        await _log(
          AppLogLevel.warn,
          '检查更新失败（已静默）：${result.errorMessage ?? '未知错误'}',
        );
      } else {
        _lastCheck = result;
        await _log(
          AppLogLevel.error,
          '检查更新失败：${result.errorMessage ?? '未知错误'}',
        );
      }
      return result;
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  Future<UpdateCheckResult> _checkIos({required bool silent}) async {
    if (!_androidClient.isConfigured) {
      final result = UpdateCheckResult.failed(
        currentVersion: _currentVersion,
        message: iosNonStoreMessage,
      );
      if (!silent) {
        _lastCheck = result;
        _lastError = iosNonStoreMessage;
      }
      return result;
    }

    final result = await _androidClient.checkForUpdate(
      currentVersion: _currentVersion,
      platformCandidates: _platformCandidates,
    );

    if (result.hasUpdate) {
      final noted = UpdateCheckResult(
        status: UpdateCheckStatus.available,
        currentVersion: result.currentVersion,
        manifest: result.manifest,
        asset: null,
        matchedPlatformKey: result.matchedPlatformKey,
        errorMessage: iosNonStoreMessage,
      );
      return await _applyCheckResult(noted, silent: silent);
    }

    if (result.status == UpdateCheckStatus.upToDate) {
      return await _applyCheckResult(result, silent: silent);
    }

    final fallback = UpdateCheckResult.failed(
      currentVersion: _currentVersion,
      message: iosNonStoreMessage,
      manifest: result.manifest,
    );
    _lastError = iosNonStoreMessage;
    if (silent) {
      await _log(
        AppLogLevel.warn,
        '检查更新失败（已静默）：$iosNonStoreMessage',
      );
    } else {
      _lastCheck = fallback;
    }
    return fallback;
  }

  Future<UpdateCheckResult> _applyCheckResult(
    UpdateCheckResult result, {
    required bool silent,
  }) async {
    switch (result.status) {
      case UpdateCheckStatus.upToDate:
        await _prefs.clearAvailableUpdate();
        if (!silent) {
          _lastCheck = result;
          await _log(
            AppLogLevel.info,
            '检查更新：已最新 current=${result.currentVersion} '
            'latest=${result.latestVersion ?? result.currentVersion}',
          );
        }
      case UpdateCheckStatus.available:
        final version = result.latestVersion;
        if (silent &&
            version != null &&
            !await _prefs.shouldPromptFor(version)) {
          await _log(
            AppLogLevel.info,
            '检查更新：发现已跳过版本 current=${result.currentVersion} '
            'latest=$version（静默）',
          );
          return result;
        }
        if (!silent) {
          await _prefs.clearSkippedUpdateVersion();
        }
        if (version != null) {
          await _prefs.setAvailableUpdate(version);
        }
        _lastCheck = result;
        await _log(
          AppLogLevel.info,
          '检查更新：发现新版本 current=${result.currentVersion} '
          'latest=${result.latestVersion} '
          'platform=${result.matchedPlatformKey}'
          '${silent ? '（静默）' : ''}',
        );
      case UpdateCheckStatus.noPlatformAsset:
        if (!silent) {
          _lastCheck = result;
          _lastError = result.errorMessage;
          await _log(
            AppLogLevel.warn,
            '检查更新：清单无本平台包 latest=${result.latestVersion}',
          );
        }
      case UpdateCheckStatus.notConfigured:
        if (!silent) {
          _lastCheck = result;
          _lastError = result.errorMessage;
          await _log(AppLogLevel.warn, '检查更新：未配置更新源');
        }
      case UpdateCheckStatus.failed:
        _lastError = result.errorMessage;
        if (silent) {
          await _log(
            AppLogLevel.warn,
            '检查更新失败（已静默）：${result.errorMessage ?? '未知错误'}',
          );
        } else {
          _lastCheck = result;
          await _log(
            AppLogLevel.error,
            '检查更新失败：${result.errorMessage ?? '未知错误'}',
          );
        }
    }
    return result;
  }

  /// 请求取消当前下载（下一 chunk 生效）。
  void cancelDownload() {
    if (!_downloading) return;
    _cancelRequested = true;
    _progressLabel = '正在取消…';
    notifyListeners();
  }

  /// Android：下载 + sha256 + 调起安装。iOS 直接失败。
  ///
  /// 安装前会重新 check，避免长时间持有过期清单。
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
    if (_downloading) return false;

    _downloading = true;
    _cancelRequested = false;
    _downloadProgress = null;
    _progressLabel = '准备下载…';
    _lastError = null;
    _downloadedFile = null;
    notifyListeners();

    try {
      await ensureCurrentVersion();
      final fresh = await _androidClient.checkForUpdate(
        currentVersion: _currentVersion,
        platformCandidates: _platformCandidates,
      );
      if (_cancelRequested) {
        throw const UpdateException(kUpdateDownloadCancelledMessage);
      }
      final check = (fresh.hasUpdate && fresh.asset != null)
          ? fresh
          : (result ?? _lastCheck);
      if (check == null || !check.hasUpdate || check.asset == null) {
        _lastError = fresh.hasUpdate ? '获取更新信息失败，请重试' : '没有可安装的更新';
        _progressLabel = null;
        notifyListeners();
        return false;
      }
      _lastCheck = check;

      final file = await _androidClient.downloadVerifyAndInstall(
        check.asset!,
        _apkInstaller,
        onProgress: (p) {
          _downloadProgress = p;
          _progressLabel = _formatDownloadProgress(p);
          notifyListeners();
        },
        shouldCancel: () => _cancelRequested,
      );
      if (_cancelRequested) {
        throw const UpdateException(kUpdateDownloadCancelledMessage);
      }
      _downloadedFile = file;
      _progressLabel = '下载完成，已调起安装器';
      await _log(
        AppLogLevel.info,
        '更新包已下载并调起安装：${file.path}',
      );
      return true;
    } on UpdateException catch (e) {
      _lastError = friendlyUpdateInstallError(e);
      _progressLabel = null;
      final cancelled = isUpdateDownloadCancelled(e);
      await _log(
        cancelled ? AppLogLevel.info : AppLogLevel.error,
        cancelled ? '用户取消下载更新' : '下载/安装失败：$_lastError',
      );
      return false;
    } catch (e) {
      _lastError = friendlyUpdateInstallError(e);
      _progressLabel = null;
      await _log(AppLogLevel.error, '下载/安装失败：$_lastError');
      return false;
    } finally {
      _downloading = false;
      _cancelRequested = false;
      notifyListeners();
    }
  }

  String _formatDownloadProgress(UpdateDownloadProgress p) {
    final total = p.total;
    if (total != null && total > 0) {
      final mb = (total / (1024 * 1024)).toStringAsFixed(1);
      final pct = ((p.received / total) * 100).clamp(0, 100).toStringAsFixed(0);
      return '正在下载更新… $pct%（约 $mb MB）';
    }
    if (p.received <= 0) return '开始下载…';
    final receivedMb = (p.received / (1024 * 1024)).toStringAsFixed(1);
    return '正在下载更新… 已下载 $receivedMb MB';
  }

  void clearResult() {
    _lastCheck = null;
    _lastError = null;
    _downloadProgress = null;
    _progressLabel = null;
    _downloadedFile = null;
    notifyListeners();
  }

  Future<void> _log(AppLogLevel level, String message) async {
    final logs = _appLogs;
    if (logs == null) return;
    try {
      await logs.append(
        level: level,
        source: AppLogSources.updater,
        message: message,
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _androidClient.close();
    if (_ownsPrefs) {
      _prefs.dispose();
    }
    super.dispose();
  }
}
