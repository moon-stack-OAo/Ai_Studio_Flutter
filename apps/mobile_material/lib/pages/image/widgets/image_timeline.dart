import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';

import '../../../widgets/collapsible_prompt.dart';
import '../../../widgets/material_empty_states.dart';

/// M-ImageTimeline：竖向卡片流；回合分隔可读。
class ImageTimeline extends StatefulWidget {
  const ImageTimeline({
    super.key,
    required this.items,
    required this.loadBytes,
    required this.onPreview,
    required this.onSaveAlbum,
    this.onUseAsReference,
    this.emptyHint = '输入提示词开始生图',
    this.emptySubtitle = '在上方填写提示词后生成。',
  });

  final List<ImageItem> items;
  final Future<Uint8List?> Function(ImageRef ref) loadBytes;
  final void Function(ImageItem item, int index, ImageRef ref) onPreview;
  final void Function(ImageItem item, int index, ImageRef ref) onSaveAlbum;
  final void Function(ImageItem item, int index, ImageRef ref)?
      onUseAsReference;
  final String emptyHint;
  final String? emptySubtitle;

  @override
  State<ImageTimeline> createState() => _ImageTimelineState();
}

class _ImageTimelineState extends State<ImageTimeline> {
  final ScrollController _scroll = ScrollController();
  int _lastCount = 0;
  String _lastTail = '';

  @override
  void initState() {
    super.initState();
    _lastCount = widget.items.length;
    _lastTail = _tailKey(widget.items);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void didUpdateWidget(covariant ImageTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    final count = widget.items.length;
    final tail = _tailKey(widget.items);
    if (count != _lastCount || tail != _lastTail) {
      _lastCount = count;
      _lastTail = tail;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  String _tailKey(List<ImageItem> items) {
    if (items.isEmpty) return '';
    final last = items.reduce(
      (a, b) => a.createdAt >= b.createdAt ? a : b,
    );
    return '${last.id}:${last.status.name}:${last.images.length}';
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return MaterialContentEmpty(
        hint: widget.emptyHint,
        subtitle: widget.emptySubtitle,
      );
    }

    final sorted = List<ImageItem>.from(widget.items)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 24),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ImageTimelineTurn(
            item: sorted[index],
            turnIndex: index + 1,
            loadBytes: widget.loadBytes,
            onPreview: widget.onPreview,
            onSaveAlbum: widget.onSaveAlbum,
            onUseAsReference: widget.onUseAsReference,
          ),
        );
      },
    );
  }
}

/// 单回合卡片（供 CustomScrollView 复用）。
class ImageTimelineTurn extends StatelessWidget {
  const ImageTimelineTurn({
    super.key,
    required this.item,
    required this.turnIndex,
    required this.loadBytes,
    required this.onPreview,
    required this.onSaveAlbum,
    this.onUseAsReference,
  });

  final ImageItem item;
  final int turnIndex;
  final Future<Uint8List?> Function(ImageRef ref) loadBytes;
  final void Function(ImageItem item, int index, ImageRef ref) onPreview;
  final void Function(ImageItem item, int index, ImageRef ref) onSaveAlbum;
  final void Function(ImageItem item, int index, ImageRef ref)?
      onUseAsReference;

  String _timeLabel(int ms) {
    if (ms <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    return Card(
      margin: EdgeInsets.zero,
      color: tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: tokens.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '你 · 回合 $turnIndex · ${_timeLabel(item.createdAt)}'
              '${item.mode == ImageGenMode.edit ? ' · 图生图' : ' · 文生图'}'
              '${item.n > 1 ? ' · ${item.n}张' : ''}',
              style: TextStyle(
                fontSize: 11,
                color: tokens.inkMuted,
                fontFamily: tokens.fontFamily,
              ),
            ),
            const SizedBox(height: 6),
            CollapsiblePrompt(
              text: item.prompt,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: tokens.ink,
                fontFamily: tokens.fontFamily,
              ),
              linkColor: tokens.primary,
            ),
            const SizedBox(height: 10),
            if (item.status == ImageItemStatus.error)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: tokens.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: tokens.danger.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  item.errorMessage ?? '生成失败',
                  style: TextStyle(
                    fontSize: 13,
                    color: tokens.danger,
                    fontFamily: tokens.fontFamily,
                  ),
                ),
              )
            else if (item.status == ImageItemStatus.loading)
              _LoadingGrid(count: item.n.clamp(1, 4), tokens: tokens)
            else
              _ResultGrid(
                item: item,
                tokens: tokens,
                loadBytes: loadBytes,
                onPreview: onPreview,
                onSaveAlbum: onSaveAlbum,
                onUseAsReference: onUseAsReference,
              ),
          ],
        ),
      ),
    );
  }
}

class _LoadingGrid extends StatelessWidget {
  const _LoadingGrid({required this.count, required this.tokens});

  final int count;
  final MaterialTokens tokens;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: List.generate(count, (i) {
        return Container(
          decoration: BoxDecoration(
            color: tokens.surfaceMuted,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: tokens.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: tokens.primary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                i == 0 ? '生成中…' : '排队中…',
                style: TextStyle(
                  fontSize: 12,
                  color: tokens.inkMuted,
                  fontFamily: tokens.fontFamily,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _ResultGrid extends StatelessWidget {
  const _ResultGrid({
    required this.item,
    required this.tokens,
    required this.loadBytes,
    required this.onPreview,
    required this.onSaveAlbum,
    this.onUseAsReference,
  });

  final ImageItem item;
  final MaterialTokens tokens;
  final Future<Uint8List?> Function(ImageRef ref) loadBytes;
  final void Function(ImageItem item, int index, ImageRef ref) onPreview;
  final void Function(ImageItem item, int index, ImageRef ref) onSaveAlbum;
  final void Function(ImageItem item, int index, ImageRef ref)?
      onUseAsReference;

  @override
  Widget build(BuildContext context) {
    if (item.images.isEmpty) {
      return Text(
        '无图片',
        style: TextStyle(color: tokens.inkMuted, fontSize: 12),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: item.images.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.78,
      ),
      itemBuilder: (context, i) {
        final ref = item.images[i];
        return _ThumbCard(
          ref: ref,
          tokens: tokens,
          loadBytes: loadBytes,
          onPreview: () => onPreview(item, i, ref),
          onSaveAlbum: () => onSaveAlbum(item, i, ref),
          onUseAsReference: onUseAsReference == null
              ? null
              : () => onUseAsReference!(item, i, ref),
        );
      },
    );
  }
}

class _ThumbCard extends StatelessWidget {
  const _ThumbCard({
    required this.ref,
    required this.tokens,
    required this.loadBytes,
    required this.onPreview,
    required this.onSaveAlbum,
    this.onUseAsReference,
  });

  final ImageRef ref;
  final MaterialTokens tokens;
  final Future<Uint8List?> Function(ImageRef ref) loadBytes;
  final VoidCallback onPreview;
  final VoidCallback onSaveAlbum;
  final VoidCallback? onUseAsReference;

  Future<void> _showActions(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.zoom_in),
                title: const Text('预览'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  onPreview();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_album_outlined),
                title: const Text('存相册'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  onSaveAlbum();
                },
              ),
              if (onUseAsReference != null)
                ListTile(
                  leading: const Icon(Icons.add_photo_alternate_outlined),
                  title: const Text('用作参考'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onUseAsReference!();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Material(
            color: tokens.surfaceMuted,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPreview,
              onLongPress: () => _showActions(context),
              child: _ThumbImage(ref: ref, loadBytes: loadBytes),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 0,
          runSpacing: 0,
          children: [
            TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onPreview,
              child: const Text('预览'),
            ),
            TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onSaveAlbum,
              child: const Text('存相册'),
            ),
            if (onUseAsReference != null)
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: onUseAsReference,
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
                label: const Text('参考'),
              ),
          ],
        ),
      ],
    );
  }
}

class _ThumbImage extends StatefulWidget {
  const _ThumbImage({required this.ref, required this.loadBytes});

  final ImageRef ref;
  final Future<Uint8List?> Function(ImageRef ref) loadBytes;

  @override
  State<_ThumbImage> createState() => _ThumbImageState();
}

class _ThumbImageState extends State<_ThumbImage> {
  Uint8List? _bytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _ThumbImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ref.src != widget.ref.src ||
        oldWidget.ref.type != widget.ref.type) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    if (widget.ref.type == ImageRefType.url) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (widget.ref.type == ImageRefType.file) {
      final f = File(widget.ref.src);
      if (await f.exists()) {
        final b = await f.readAsBytes();
        if (mounted) {
          setState(() {
            _bytes = b;
            _loading = false;
          });
        }
        return;
      }
    }
    final b = await widget.loadBytes(widget.ref);
    if (mounted) {
      setState(() {
        _bytes = b;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_bytes != null) {
      return Image.memory(_bytes!, fit: BoxFit.cover);
    }
    if (widget.ref.type == ImageRefType.url) {
      return Image.network(widget.ref.src, fit: BoxFit.cover);
    }
    return const Center(child: Icon(Icons.broken_image_outlined));
  }
}
