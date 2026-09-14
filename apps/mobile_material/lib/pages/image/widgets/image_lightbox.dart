import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';

import '../../../shell/back_host.dart';

/// 灯箱图片来源（`IMG-TURN-REF` / `CHAT-ATTACH` / 结果时间线可区分）。
enum ImageLightboxSource {
  /// 用户回合参考图（`*-TURN-REF`）。
  reference,

  /// 生成结果图。
  result,

  /// 对话用户消息附图（`CHAT-ATTACH`）。
  attachment,
}

extension ImageLightboxSourceLabel on ImageLightboxSource {
  String get label => switch (this) {
        ImageLightboxSource.reference => '参考',
        ImageLightboxSource.result => '结果',
        ImageLightboxSource.attachment => '附图',
      };
}

/// M-Lightbox：全屏预览；系统返回先关灯箱。
class ImageLightbox extends StatelessWidget {
  const ImageLightbox({
    super.key,
    required this.ref,
    required this.bytes,
    this.source = ImageLightboxSource.result,
    this.onSaveAlbum,
    this.onShare,
    this.onUseAsReference,
  });

  final ImageRef ref;
  final Uint8List? bytes;
  final ImageLightboxSource source;
  final VoidCallback? onSaveAlbum;
  final VoidCallback? onShare;
  final VoidCallback? onUseAsReference;

  static Future<void> show(
    BuildContext context, {
    required ImageRef ref,
    required Future<Uint8List?> Function() loadBytes,
    ImageLightboxSource source = ImageLightboxSource.result,
    VoidCallback? onSaveAlbum,
    VoidCallback? onShare,
    VoidCallback? onUseAsReference,
  }) async {
    final bytes = await loadBytes();
    if (!context.mounted) return;
    final tokens = materialTokensOf(context);
    await Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: true,
        barrierColor: tokens.scrim,
        transitionDuration: MaterialMotion.lightbox,
        reverseTransitionDuration: MaterialMotion.lightbox,
        pageBuilder: (ctx, animation, secondary) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: MaterialMotion.standard,
            ),
            child: ImageLightbox(
              ref: ref,
              bytes: bytes,
              source: source,
              onSaveAlbum: onSaveAlbum,
              onShare: onShare,
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
    final stage = Color.lerp(tokens.canvas, const Color(0xFF000000), 0.92)!;
    final chrome = tokens.onPrimary;
    final sourceLabel = source.label;
    return BackHost(
      child: Scaffold(
        backgroundColor: stage,
        appBar: AppBar(
          backgroundColor: stage,
          foregroundColor: chrome,
          title: Row(
            children: [
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: tokens.primary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  sourceLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: tokens.primary,
                  ),
                ),
              ),
              const Expanded(child: Text('预览')),
            ],
          ),
          leading: BackHost.closeButton(context),
          actions: [
            if (onUseAsReference != null)
              TextButton(
                onPressed: () {
                  BackHost.pop(context);
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
            if (onShare != null)
              TextButton(
                onPressed: onShare,
                child: Text(
                  '分享',
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
              child: _buildImage(tokens),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImage(MaterialTokens tokens) {
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
    return Text(
      '无法显示图片',
      style: TextStyle(color: tokens.inkMuted),
    );
  }
}
