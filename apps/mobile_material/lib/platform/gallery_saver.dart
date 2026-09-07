import 'dart:io';
import 'dart:typed_data';

import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

/// 系统相册写入结果（SYS-GALLERY）。
class GallerySaveResult {
  const GallerySaveResult._({
    required this.ok,
    this.errorMessage,
  });

  final bool ok;
  final String? errorMessage;

  factory GallerySaveResult.success() =>
      const GallerySaveResult._(ok: true);

  factory GallerySaveResult.failure(String message) =>
      GallerySaveResult._(ok: false, errorMessage: message);
}

/// 将图片 / 视频写入系统相册（gal）。
///
/// 权限拒绝时返回明确错误文案，供 SnackBar 展示。
class GallerySaver {
  const GallerySaver();

  /// 确保相册写入权限；拒绝返回 false。
  Future<bool> ensureAccess() async {
    try {
      if (await Gal.hasAccess()) return true;
      return await Gal.requestAccess();
    } on GalException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<GallerySaveResult> saveImageFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return GallerySaveResult.failure('图片文件不存在');
    }
    return _guarded(() async {
      if (!await ensureAccess()) {
        return GallerySaveResult.failure('未授予相册权限，无法保存');
      }
      await Gal.putImage(path);
      return GallerySaveResult.success();
    });
  }

  Future<GallerySaveResult> saveImageBytes(
    Uint8List bytes, {
    String name = 'ai-studio-image',
  }) async {
    if (bytes.isEmpty) {
      return GallerySaveResult.failure('图片数据为空');
    }
    return _guarded(() async {
      if (!await ensureAccess()) {
        return GallerySaveResult.failure('未授予相册权限，无法保存');
      }
      await Gal.putImageBytes(bytes, name: name);
      return GallerySaveResult.success();
    });
  }

  Future<GallerySaveResult> saveVideoFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return GallerySaveResult.failure('视频文件不存在');
    }
    return _guarded(() async {
      if (!await ensureAccess()) {
        return GallerySaveResult.failure('未授予相册权限，无法保存');
      }
      await Gal.putVideo(path);
      return GallerySaveResult.success();
    });
  }

  /// 字节落临时文件再写入相册（适合 memory / 无本地路径）。
  Future<GallerySaveResult> saveVideoBytes(
    Uint8List bytes, {
    String nameHint = 'ai-studio-video',
  }) async {
    if (bytes.isEmpty) {
      return GallerySaveResult.failure('视频数据为空');
    }
    File? tmp;
    try {
      final dir = await getTemporaryDirectory();
      final safe = nameHint.replaceAll(RegExp(r'[^\w\-.]'), '_');
      tmp = File(
        '${dir.path}${Platform.pathSeparator}'
        '$safe-${DateTime.now().millisecondsSinceEpoch}.mp4',
      );
      await tmp.writeAsBytes(bytes, flush: true);
      return await saveVideoFile(tmp.path);
    } catch (e) {
      return GallerySaveResult.failure(_friendly(e));
    } finally {
      try {
        if (tmp != null && await tmp.exists()) await tmp.delete();
      } catch (_) {}
    }
  }

  Future<GallerySaveResult> _guarded(
    Future<GallerySaveResult> Function() action,
  ) async {
    try {
      return await action();
    } on GalException catch (e) {
      return GallerySaveResult.failure(_galMessage(e));
    } catch (e) {
      return GallerySaveResult.failure(_friendly(e));
    }
  }

  String _galMessage(GalException e) {
    switch (e.type) {
      case GalExceptionType.accessDenied:
        return '未授予相册权限，无法保存';
      case GalExceptionType.notEnoughSpace:
        return '存储空间不足，无法保存到相册';
      case GalExceptionType.notSupportedFormat:
        return '不支持的媒体格式，无法保存到相册';
      case GalExceptionType.unexpected:
        return '保存到相册失败：${e.type.message}';
    }
  }

  String _friendly(Object err) {
    final msg = err.toString().trim();
    if (msg.isEmpty) return '保存到相册失败';
    if (msg.toLowerCase().contains('access') ||
        msg.contains('权限') ||
        msg.contains('denied')) {
      return '未授予相册权限，无法保存';
    }
    return '保存到相册失败：$msg';
  }
}
