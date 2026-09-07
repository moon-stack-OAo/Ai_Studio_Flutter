import 'dart:io';

import 'package:share_plus/share_plus.dart';

/// 系统分享结果（SYS-SHARE）。
class ShareHelperResult {
  const ShareHelperResult._({
    required this.ok,
    this.dismissed = false,
    this.errorMessage,
  });

  final bool ok;
  final bool dismissed;
  final String? errorMessage;

  factory ShareHelperResult.success() =>
      const ShareHelperResult._(ok: true);

  factory ShareHelperResult.dismissed() =>
      const ShareHelperResult._(ok: true, dismissed: true);

  factory ShareHelperResult.failure(String message) =>
      ShareHelperResult._(ok: false, errorMessage: message);
}

/// 调起系统 Share sheet（share_plus）。
class ShareHelper {
  const ShareHelper();

  Future<ShareHelperResult> shareLocalFile(
    String path, {
    String? mimeType,
    String? name,
  }) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return ShareHelperResult.failure('文件路径为空');
    }
    if (trimmed.startsWith('http') ||
        trimmed.startsWith('memory://') ||
        trimmed.startsWith('data:')) {
      return ShareHelperResult.failure('没有可分享的本地文件');
    }

    final filePath =
        trimmed.startsWith('file:') ? Uri.parse(trimmed).toFilePath() : trimmed;
    final file = File(filePath);
    if (!await file.exists()) {
      return ShareHelperResult.failure('本地文件不存在');
    }

    try {
      final xfile = XFile(
        filePath,
        mimeType: mimeType,
        name: name ?? _fileName(filePath),
      );
      final result = await SharePlus.instance.share(
        ShareParams(files: [xfile]),
      );
      switch (result.status) {
        case ShareResultStatus.success:
          return ShareHelperResult.success();
        case ShareResultStatus.dismissed:
          return ShareHelperResult.dismissed();
        case ShareResultStatus.unavailable:
          return ShareHelperResult.failure('当前设备不支持系统分享');
      }
    } catch (e) {
      return ShareHelperResult.failure(_friendly(e));
    }
  }

  String _fileName(String path) {
    final sep = Platform.pathSeparator;
    final i = path.replaceAll('/', sep).lastIndexOf(sep);
    if (i < 0 || i >= path.length - 1) return 'ai-studio-share';
    return path.substring(i + 1);
  }

  String _friendly(Object err) {
    final msg = err.toString().trim();
    if (msg.isEmpty) return '分享失败';
    return '分享失败：$msg';
  }
}
