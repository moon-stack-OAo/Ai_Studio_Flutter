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

/// M-Lightbox：全屏预览 + 滑动切换；系统返回先关灯箱。
class ImageLightbox extends StatefulWidget {
  const ImageLightbox({
    super.key,
    required this.refs,
    required this.initialIndex,
    required this.bytesByIndex,
    this.source = ImageLightboxSource.result,
    this.loadBytesFor,
    this.onSaveAlbum,
    this.onShare,
    this.onUseAsReference,
  });

  final List<ImageRef> refs;
  final int initialIndex;
  final Map<int, Uint8List?> bytesByIndex;
  final ImageLightboxSource source;
  final Future<Uint8List?> Function(ImageRef ref)? loadBytesFor;
  final void Function(ImageRef ref)? onSaveAlbum;
  final void Function(ImageRef ref)? onShare;
  final void Function(ImageRef ref)? onUseAsReference;

  static Future<void> show(
    BuildContext context, {
    required ImageRef ref,
    required Future<Uint8List?> Function() loadBytes,
    List<ImageRef>? refs,
    int initialIndex = 0,
    ImageLightboxSource source = ImageLightboxSource.result,
    Future<Uint8List?> Function(ImageRef ref)? loadBytesFor,
    void Function(ImageRef ref)? onSaveAlbum,
    void Function(ImageRef ref)? onShare,
    void Function(ImageRef ref)? onUseAsReference,
  }) async {
    final list =
        (refs == null || refs.isEmpty) ? <ImageRef>[ref] : List<ImageRef>.from(refs);
    final start = initialIndex.clamp(0, list.length - 1);
    final loader = loadBytesFor;
    final bytesByIndex = <int, Uint8List?>{};
    if (loader != null) {
      bytesByIndex[start] = await loader(list[start]);
    } else {
      bytesByIndex[start] = await loadBytes();
    }
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
              refs: list,
              initialIndex: start,
              bytesByIndex: bytesByIndex,
              source: source,
              loadBytesFor: loader,
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
  State<ImageLightbox> createState() => _ImageLightboxState();
}

class _ImageLightboxState extends State<ImageLightbox> {
  late int _index;
  late final Map<int, Uint8List?> _bytes;
  late final PageController _pageController;
  bool _loading = false;

  List<ImageRef> get _refs => widget.refs;
  bool get _multi => _refs.length > 1;
  ImageRef get _current => _refs[_index];

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.refs.length - 1);
    _bytes = Map<int, Uint8List?>.from(widget.bytesByIndex);
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _ensureBytes(int index) async {
    if (_bytes.containsKey(index)) return;
    final loader = widget.loadBytesFor;
    setState(() => _loading = true);
    try {
      final ref = _refs[index];
      Uint8List? data;
      if (loader != null) {
        data = await loader(ref);
      } else if (ref.type == ImageRefType.file) {
        final file = File(ref.src);
        if (file.existsSync()) data = await file.readAsBytes();
      }
      if (mounted) {
        setState(() {
          _bytes[index] = data;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _bytes[index] = null;
          _loading = false;
        });
      }
    }
  }

  void _onPageChanged(int page) {
    if (page == _index) return;
    setState(() => _index = page);
    _ensureBytes(page);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    final stage = Color.lerp(tokens.canvas, const Color(0xFF000000), 0.92)!;
    final chrome = tokens.onPrimary;
    final sourceLabel = widget.source.label;
    final title = _multi ? '预览（${_index + 1}/${_refs.length}）' : '预览';
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
              Expanded(child: Text(title)),
            ],
          ),
          leading: BackHost.closeButton(context),
          actions: [
            if (widget.onUseAsReference != null)
              TextButton(
                onPressed: () {
                  final ref = _current;
                  BackHost.pop(context);
                  widget.onUseAsReference!(ref);
                },
                child: Text(
                  '用作参考',
                  style: TextStyle(color: tokens.primary),
                ),
              ),
            if (widget.onSaveAlbum != null)
              TextButton(
                onPressed: () => widget.onSaveAlbum!(_current),
                child: Text(
                  '存相册',
                  style: TextStyle(color: tokens.primary),
                ),
              ),
            if (widget.onShare != null)
              TextButton(
                onPressed: () => widget.onShare!(_current),
                child: Text(
                  '分享',
                  style: TextStyle(color: tokens.primary),
                ),
              ),
          ],
        ),
        body: SafeArea(
          child: PageView.builder(
            controller: _pageController,
            itemCount: _refs.length,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, i) {
              final ref = _refs[i];
              final bytes = _bytes[i];
              final waiting = _loading && !_bytes.containsKey(i);
              if (waiting) {
                return Center(
                  child: CircularProgressIndicator(color: tokens.primary),
                );
              }
              return Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4,
                  child: _buildImage(tokens, ref, bytes),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildImage(
    MaterialTokens tokens,
    ImageRef ref,
    Uint8List? bytes,
  ) {
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(bytes, fit: BoxFit.contain);
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
