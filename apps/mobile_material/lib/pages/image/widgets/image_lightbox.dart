import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';

/// M-Lightbox：全屏预览；系统返回先关灯箱。
class ImageLightbox extends StatelessWidget {
  const ImageLightbox({
    super.key,
    required this.ref,
    required this.bytes,
    this.onSaveAlbum,
    this.onUseAsReference,
  });

  final ImageRef ref;
  final Uint8List? bytes;
  final VoidCallback? onSaveAlbum;
  final VoidCallback? onUseAsReference;

  static Future<void> show(
    BuildContext context, {
    required ImageRef ref,
    required Future<Uint8List?> Function() loadBytes,
    VoidCallback? onSaveAlbum,
    VoidCallback? onUseAsReference,
  }) async {
    final bytes = await loadBytes();
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black87,
        pageBuilder: (ctx, animation, secondary) {
          return FadeTransition(
            opacity: animation,
            child: ImageLightbox(
              ref: ref,
              bytes: bytes,
              onSaveAlbum: onSaveAlbum,
              onUseAsReference: onUseAsReference,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('预览'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          if (onUseAsReference != null)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                onUseAsReference!();
              },
              child: Text(
                '用作参考',
                style: TextStyle(color: tokens.primary),
              ),
            ),
          if (onSaveAlbum != null)
            TextButton(
              onPressed: onSaveAlbum,
              child: Text(
                '存相册',
                style: TextStyle(color: tokens.primary),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4,
            child: _buildImage(),
          ),
        ),
      ),
    );
  }

  Widget _buildImage() {
    if (bytes != null && bytes!.isNotEmpty) {
      return Image.memory(bytes!, fit: BoxFit.contain);
    }
    if (ref.type == ImageRefType.file) {
      final file = File(ref.src);
      if (file.existsSync()) {
        return Image.file(file, fit: BoxFit.contain);
      }
    }
    if (ref.type == ImageRefType.url) {
      return Image.network(ref.src, fit: BoxFit.contain);
    }
    return const Text(
      '无法显示图片',
      style: TextStyle(color: Colors.white70),
    );
  }
}
