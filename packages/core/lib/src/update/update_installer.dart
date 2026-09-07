import 'dart:io';

import 'update_client.dart';

/// 拉起本地下载的安装器（桌面）。
///
/// **勿**把 [DesktopUpdateInstaller] 当作 Android APK 安装器使用。
abstract class UpdateInstaller {
  /// 启动 [installerFile]；成功后调用方可选择退出应用。
  Future<void> launch(File installerFile);
}

/// Android APK 安装抽象（真实实现放 mobile：MethodChannel / open_filex）。
///
/// 调用前须已通过 sha256 校验；实现侧负责「未知来源」权限提示。
abstract class AndroidApkInstaller {
  /// 调起系统安装器打开 [apkFile]。
  Future<void> install(File apkFile);
}

/// 测试用：记录调用而不真正安装。
class FakeAndroidApkInstaller implements AndroidApkInstaller {
  File? lastFile;
  bool throwOnInstall = false;

  @override
  Future<void> install(File apkFile) async {
    lastFile = apkFile;
    if (throwOnInstall) {
      throw const UpdateException('fake apk install failed');
    }
  }
}

/// 使用 `Process.start` 拉起 .exe / .msi / .dmg 等。
class DesktopUpdateInstaller implements UpdateInstaller {
  const DesktopUpdateInstaller();

  @override
  Future<void> launch(File installerFile) async {
    if (!await installerFile.exists()) {
      throw UpdateException('安装包不存在：${installerFile.path}');
    }
    final path = installerFile.path;
    final lower = path.toLowerCase();

    try {
      if (Platform.isWindows) {
        if (lower.endsWith('.msi')) {
          await Process.start(
            'msiexec',
            ['/i', path],
            mode: ProcessStartMode.detached,
          );
        } else {
          // .exe / NSIS setup
          await Process.start(
            path,
            const [],
            mode: ProcessStartMode.detached,
          );
        }
        return;
      }
      if (Platform.isMacOS) {
        await Process.start(
          'open',
          [path],
          mode: ProcessStartMode.detached,
        );
        return;
      }
      if (Platform.isLinux) {
        await Process.start(
          path,
          const [],
          mode: ProcessStartMode.detached,
        );
        return;
      }
      throw const UpdateException('当前平台不支持拉起安装器');
    } on UpdateException {
      rethrow;
    } catch (e) {
      throw UpdateException('无法启动安装器：$e');
    }
  }
}

/// 测试用：记录调用而不真正启动进程。
class FakeUpdateInstaller implements UpdateInstaller {
  File? lastFile;
  bool throwOnLaunch = false;

  @override
  Future<void> launch(File installerFile) async {
    lastFile = installerFile;
    if (throwOnLaunch) {
      throw const UpdateException('fake launch failed');
    }
  }
}
