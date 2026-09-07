import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 桌面直链更新控制器（检查 / 下载 / 拉起安装器）。
class UpdateController extends ChangeNotifier {
  UpdateController({
    required this._client,
    UpdateInstaller? installer,
    AppLogRepository? appLogRepository,
    String? currentVersion,
    List<String>? platformCandidates,
    this.onQuitAfterInstall,
  })  : _installer = installer ?? const DesktopUpdateInstaller(),
        _appLogs = appLogRepository,
        _injectedVersion = currentVersion,
        _platformCandidates =
            platformCandidates ?? desktopUpdatePlatformCandidates();

  final UpdateClient _client;
  final UpdateInstaller _installer;
  final AppLogRepository? _appLogs;
  final String? _injectedVersion;
  final List<String> _platformCandidates;

  /// 安装器拉起后退出应用；测试可注入。
  final Future<void> Function()? onQuitAfterInstall;

  String _currentVersion = '0.0.0';
  bool _versionReady = false;

  UpdateCheckResult? _lastCheck;
  bool _checking = false;
  bool _downloading = false;
  UpdateDownloadProgress? _downloadProgress;
  String? _lastError;
  File? _downloadedFile;

  UpdateClient get client => _client;

  String get currentVersion => _currentVersion;

  bool get isVersionReady => _versionReady;

  bool get isConfigured => _client.isConfigured;

  String get manifestUrl => _client.manifestUrl;

  UpdateCheckResult? get lastCheck => _lastCheck;

  bool get isChecking => _checking;

  bool get isDownloading => _downloading;

  UpdateDownloadProgress? get downloadProgress => _downloadProgress;

  String? get lastError => _lastError;

  File? get downloadedFile => _downloadedFile;

  bool get hasUpdate => _lastCheck?.hasUpdate ?? false;

  /// 解析本地版本（可注入；否则 `PackageInfo`）。
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
      if (!_client.isConfigured) {
        final result = UpdateCheckResult.notConfigured(_currentVersion);
        _lastCheck = result;
        await _log(
          AppLogLevel.warn,
          '检查更新：未配置更新源',
        );
        return result;
      }

      final result = await _client.checkForUpdate(
        currentVersion: _currentVersion,
        platformCandidates: _platformCandidates,
      );
      _lastCheck = result;

      switch (result.status) {
        case UpdateCheckStatus.upToDate:
          await _log(
            AppLogLevel.info,
            '检查更新：已最新 current=${result.currentVersion} '
            'latest=${result.latestVersion ?? result.currentVersion}',
          );
        case UpdateCheckStatus.available:
          await _log(
            AppLogLevel.info,
            '检查更新：发现新版本 current=${result.currentVersion} '
            'latest=${result.latestVersion} '
            'platform=${result.matchedPlatformKey}',
          );
        case UpdateCheckStatus.noPlatformAsset:
          await _log(
            AppLogLevel.warn,
            '检查更新：清单无本平台包 latest=${result.latestVersion}',
          );
          _lastError = result.errorMessage;
        case UpdateCheckStatus.notConfigured:
          await _log(AppLogLevel.warn, '检查更新：未配置更新源');
          _lastError = result.errorMessage;
        case UpdateCheckStatus.failed:
          await _log(
            AppLogLevel.error,
            '检查更新失败：${result.errorMessage ?? '未知错误'}',
          );
          _lastError = result.errorMessage;
      }
      return result;
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  /// 下载并拉起安装器；成功后可选退出应用。
  Future<bool> downloadAndInstall({
    UpdateCheckResult? result,
    bool quitAfterLaunch = true,
  }) async {
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
    _downloadedFile = null;
    notifyListeners();

    try {
      final file = await _client.downloadInstaller(
        check.asset!,
        onProgress: (p) {
          _downloadProgress = p;
          notifyListeners();
        },
      );
      _downloadedFile = file;
      await _log(
        AppLogLevel.info,
        '更新包已下载：${file.path} '
        '(${_downloadProgress?.received ?? 0} bytes)',
      );

      await _installer.launch(file);
      await _log(
        AppLogLevel.info,
        '已拉起安装器：${file.path}',
      );

      if (quitAfterLaunch) {
        final quit = onQuitAfterInstall;
        if (quit != null) {
          await quit();
        } else {
          exit(0);
        }
      }
      return true;
    } on UpdateException catch (e) {
      _lastError = e.message;
      await _log(AppLogLevel.error, '下载/安装失败：${e.message}');
      return false;
    } catch (e) {
      _lastError = e.toString();
      await _log(AppLogLevel.error, '下载/安装失败：$e');
      return false;
    } finally {
      _downloading = false;
      notifyListeners();
    }
  }

  void clearResult() {
    _lastCheck = null;
    _lastError = null;
    _downloadProgress = null;
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
    _client.close();
    super.dispose();
  }
}
