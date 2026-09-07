import 'dart:io';

import 'package:core/core.dart';
import 'package:open_filex/open_filex.dart';

/// 通过 `open_filex` 调起系统安装器打开 APK。
///
/// 需要 AndroidManifest 声明 `REQUEST_INSTALL_PACKAGES`；
/// 用户须在系统设置中允许「安装未知应用」。
class OpenFileAndroidApkInstaller implements AndroidApkInstaller {
  const OpenFileAndroidApkInstaller();

  @override
  Future<void> install(File apkFile) async {
    if (!await apkFile.exists()) {
      throw UpdateException('安装包不存在：${apkFile.path}');
    }
    final result = await OpenFilex.open(
      apkFile.path,
      type: 'application/vnd.android.package-archive',
    );
    switch (result.type) {
      case ResultType.done:
        return;
      case ResultType.noAppToOpen:
        throw const UpdateException(
          '无法打开安装器。请确认已允许「安装未知应用」，或手动安装已下载的 APK。',
        );
      case ResultType.permissionDenied:
        throw const UpdateException(
          '未开启「允许安装未知应用」。请在系统设置中为本应用开启后重试。',
        );
      case ResultType.fileNotFound:
        throw UpdateException('安装包不存在：${apkFile.path}');
      case ResultType.error:
        final msg = result.message.trim();
        throw UpdateException(
          msg.isEmpty ? '调起安装器失败' : '调起安装器失败：$msg',
        );
    }
  }
}
