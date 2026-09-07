import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 参考图上传前压缩参数（对齐现网 `imageCompress.js`）。
class ImageCompressOptions {
  const ImageCompressOptions({
    this.maxEdge = 1280,
    this.quality = 0.85,
    this.skipBelowBytes = 1024 * 1024,
  });

  /// 图生视频默认：略收紧。
  static const videoDefault = ImageCompressOptions(
    maxEdge: 1024,
    quality: 0.75,
    skipBelowBytes: 0,
  );

  /// 图生视频 HTTP 413 重试：更激进。
  static const videoAggressive = ImageCompressOptions(
    maxEdge: 768,
    quality: 0.65,
    skipBelowBytes: 0,
  );

  final int maxEdge;
  final double quality;
  final int skipBelowBytes;
}

/// 压缩结果（JPEG）。
class CompressedImage {
  const CompressedImage({
    required this.bytes,
    required this.fileName,
    this.mimeType = 'image/jpeg',
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;

  String get dataUrl => 'data:$mimeType;base64,${base64Encode(bytes)}';
}

String _jpegFileName(String nameHint) {
  final base = nameHint.trim().isEmpty ? 'image' : nameHint.trim();
  final withoutExt = base.contains('.')
      ? base.substring(0, base.lastIndexOf('.'))
      : base;
  final safe = withoutExt.isEmpty ? 'image' : withoutExt;
  return '$safe.jpg';
}

bool _looksLikeJpeg(Uint8List bytes) {
  return bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF;
}

/// 参考图上传前压缩，降低图生视频 / 图生图 HTTP 413 概率。
CompressedImage compressImageBytes(
  Uint8List bytes, {
  ImageCompressOptions options = const ImageCompressOptions(),
  String fileName = 'image.png',
}) {
  if (bytes.isEmpty) {
    throw StateError('缺少图片文件');
  }

  final maxEdge = options.maxEdge > 0 ? options.maxEdge : 1280;
  final quality = (options.quality > 0 && options.quality <= 1)
      ? options.quality
      : 0.85;
  final skipBelow = options.skipBelowBytes;
  final outName = _jpegFileName(fileName);

  late final img.Image decoded;
  try {
    final parsed = img.decodeImage(bytes);
    if (parsed == null) {
      throw StateError('图片解码失败');
    }
    decoded = parsed;
  } catch (e) {
    if (e is StateError) rethrow;
    final msg = e.toString();
    throw StateError(
      msg.isNotEmpty && msg != 'null' ? '图片解码失败：$msg' : '图片解码失败',
    );
  }

  final srcW = decoded.width;
  final srcH = decoded.height;
  if (srcW <= 0 || srcH <= 0) {
    return CompressedImage(bytes: bytes, fileName: fileName);
  }

  final longest = srcW > srcH ? srcW : srcH;
  final scale = longest > maxEdge ? maxEdge / longest : 1.0;
  final needResize = scale < 1;
  final sizeOk = bytes.length < skipBelow;
  if (!needResize && sizeOk && _looksLikeJpeg(bytes)) {
    return CompressedImage(
      bytes: bytes,
      fileName: outName,
      mimeType: 'image/jpeg',
    );
  }

  img.Image resized = decoded;
  if (needResize) {
    final dstW = (srcW * scale).round().clamp(1, 1 << 30);
    final dstH = (srcH * scale).round().clamp(1, 1 << 30);
    resized = img.copyResize(
      decoded,
      width: dstW,
      height: dstH,
      interpolation: img.Interpolation.linear,
    );
  }

  final jpgQuality = (quality * 100).round().clamp(1, 100);
  final encoded = img.encodeJpg(resized, quality: jpgQuality);
  if (encoded.isEmpty) {
    return CompressedImage(bytes: bytes, fileName: fileName);
  }
  if (encoded.length >= bytes.length && !needResize) {
    return CompressedImage(bytes: bytes, fileName: fileName);
  }
  return CompressedImage(
    bytes: Uint8List.fromList(encoded),
    fileName: outName,
    mimeType: 'image/jpeg',
  );
}
