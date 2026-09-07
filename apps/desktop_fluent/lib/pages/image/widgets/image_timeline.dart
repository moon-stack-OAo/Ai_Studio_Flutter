import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../../widgets/collapsible_prompt.dart';
import '../../../widgets/fluent_empty_states.dart';

/// F-ImageTimeline：time-split + prompt bubble + 自适应结果网格。
class ImageTimeline extends StatefulWidget {
  const ImageTimeline({
    super.key,
    required this.items,
    required this.loadBytes,
    required this.onPreview,
    required this.onSave,
    this.onUseAsReference,
    this.emptyHint = '输入提示词开始生图',
    this.emptySubtitle = '在右侧参数区填写提示词后生成。',
  });

  final List<ImageItem> items;
  final Future<Uint8List?> Function(ImageRef ref) loadBytes;
  final void Function(ImageItem item, int index, ImageRef ref) onPreview;
  final void Function(ImageItem item, int index, ImageRef ref) onSave;
  final void Function(ImageItem item, int index, ImageRef ref)?
      onUseAsReference;
  final String emptyHint;
  final String? emptySubtitle;

  @override
  State<ImageTimeline> createState() => _ImageTimelineState();
}

class _ImageTimelineState extends State<ImageTimeline> {
  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    if (widget.items.isEmpty) {
      return FluentContentEmpty(
        hint: widget.emptyHint,
        subtitle: widget.emptySubtitle,
      );
    }

    // 最新在上：进页即见最新，无需自动滚底。
    final sorted = List<ImageItem>.from(widget.items)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final total = sorted.length;

    final children = <Widget>[];
    for (var i = 0; i < sorted.length; i++) {
      final item = sorted[i];
      children.add(
        _TimeSplit(label: formatTimeSplitLabel(item.createdAt), tokens: tokens),
      );
      children.add(
        _TurnCard(
          item: item,
          turnIndex: total - i,
          tokens: tokens,
          loadBytes: widget.loadBytes,
          onPreview: widget.onPreview,
          onSave: widget.onSave,
          onUseAsReference: widget.onUseAsReference,
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      children: children,
    );
  }
}

/// 今天/昨天 + HH:mm；更早则月日。
String formatTimeSplitLabel(int ms) {
  if (ms <= 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(dt.year, dt.month, dt.day);
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  final clock = '$hh:$mm';
  if (day == today) return '今天 $clock';
  if (day == today.subtract(const Duration(days: 1))) return '昨天 $clock';
  return '${dt.month}/${dt.day} $clock';
}

class _TimeSplit extends StatelessWidget {
  const _TimeSplit({required this.label, required this.tokens});

  final String label;
  final FluentTokens tokens;

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    tokens.border.withValues(alpha: 0),
                    tokens.border,
                    tokens.border.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: tokens.border),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: tokens.inkMuted,
                  fontFamily: tokens.fontFamily,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    tokens.border.withValues(alpha: 0),
                    tokens.border,
                    tokens.border.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TurnCard extends StatelessWidget {
  const _TurnCard({
    required this.item,
    required this.turnIndex,
    required this.tokens,
    required this.loadBytes,
    required this.onPreview,
    required this.onSave,
    this.onUseAsReference,
  });

  final ImageItem item;
  final int turnIndex;
  final FluentTokens tokens;
  final Future<Uint8List?> Function(ImageRef ref) loadBytes;
  final void Function(ImageItem item, int index, ImageRef ref) onPreview;
  final void Function(ImageItem item, int index, ImageRef ref) onSave;
  final void Function(ImageItem item, int index, ImageRef ref)?
      onUseAsReference;

  String _clock(int ms) {
    if (ms <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: tokens.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: tokens.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '你 · 回合 $turnIndex · ${_clock(item.createdAt)}'
                      '${item.mode == ImageGenMode.edit ? ' · 图生图' : ''}'
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
                        height: 1.55,
                        color: tokens.inkSecondary,
                        fontFamily: tokens.fontFamily,
                      ),
                      linkColor: tokens.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (item.status == ImageItemStatus.error)
            InfoBar(
              title: Text(item.errorMessage ?? '生成失败'),
              severity: InfoBarSeverity.error,
            )
          else if (item.status == ImageItemStatus.loading)
            _AdaptiveGrid(
              tokens: tokens,
              count: item.n.clamp(1, 4),
              builder: (index, cellSize) => _BusyCard(
                label: index == 0 ? '生成中…' : '排队中…',
                tokens: tokens,
                size: cellSize,
              ),
            )
          else
            _AdaptiveGrid(
              tokens: tokens,
              count: item.images.length,
              builder: (index, cellSize) {
                final ref = item.images[index];
                return _HoverCard(
                  ref: ref,
                  tokens: tokens,
                  size: cellSize,
                  loadBytes: loadBytes,
                  onPreview: () => onPreview(item, index, ref),
                  onSave: () => onSave(item, index, ref),
                  onUseAsReference: onUseAsReference == null
                      ? null
                      : () => onUseAsReference!(item, index, ref),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _AdaptiveGrid extends StatelessWidget {
  const _AdaptiveGrid({
    required this.tokens,
    required this.count,
    required this.builder,
  });

  final FluentTokens tokens;
  final int count;
  final Widget Function(int index, double cellSize) builder;

  static const double _minCell = 160;
  static const double _gap = 12;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return Text(
        '无图片',
        style: TextStyle(color: tokens.inkMuted, fontSize: 12),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final cols = (width / (_minCell + _gap)).floor().clamp(1, 4);
        final cell =
            ((width - _gap * (cols - 1)) / cols).clamp(_minCell, 400.0);
        return Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [
            for (var i = 0; i < count; i++) builder(i, cell),
          ],
        );
      },
    );
  }
}

class _BusyCard extends StatelessWidget {
  const _BusyCard({
    required this.label,
    required this.tokens,
    required this.size,
  });

  final String label;
  final FluentTokens tokens;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tokens.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const ProgressRing(strokeWidth: 2.5),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: tokens.primaryPressed,
              fontFamily: tokens.fontFamily,
            ),
          ),
        ],
      ),
    );
  }
}

class _HoverCard extends StatefulWidget {
  const _HoverCard({
    required this.ref,
    required this.tokens,
    required this.size,
    required this.loadBytes,
    required this.onPreview,
    required this.onSave,
    this.onUseAsReference,
  });

  final ImageRef ref;
  final FluentTokens tokens;
  final double size;
  final Future<Uint8List?> Function(ImageRef ref) loadBytes;
  final VoidCallback onPreview;
  final VoidCallback onSave;
  final VoidCallback? onUseAsReference;

  @override
  State<_HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<_HoverCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPreview,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  color: tokens.surfaceMuted,
                  foregroundDecoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: tokens.border),
                  ),
                  child: _ThumbImage(
                    ref: widget.ref,
                    loadBytes: widget.loadBytes,
                  ),
                ),
              ),
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: AnimatedOpacity(
                  opacity: _hover ? 1 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: IgnorePointer(
                    ignoring: !_hover,
                    child: Row(
                      children: [
                        _ToolBtn(
                          label: '预览',
                          tokens: tokens,
                          onPressed: widget.onPreview,
                        ),
                        const SizedBox(width: 4),
                        _ToolBtn(
                          label: '另存为',
                          tokens: tokens,
                          onPressed: widget.onSave,
                        ),
                        if (widget.onUseAsReference != null) ...[
                          const SizedBox(width: 4),
                          _ToolBtn(
                            label: '作参考',
                            tokens: tokens,
                            onPressed: widget.onUseAsReference!,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolBtn extends StatelessWidget {
  const _ToolBtn({
    required this.label,
    required this.tokens,
    required this.onPressed,
  });

  final String label;
  final FluentTokens tokens;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tokens.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: tokens.border),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: tokens.ink,
              fontFamily: tokens.fontFamily,
            ),
          ),
        ),
      ),
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
      return const Center(child: ProgressRing(strokeWidth: 2));
    }
    if (_bytes != null) {
      return Image.memory(_bytes!, fit: BoxFit.cover);
    }
    if (widget.ref.type == ImageRefType.url) {
      return Image.network(widget.ref.src, fit: BoxFit.cover);
    }
    return const Center(child: Icon(FluentIcons.photo));
  }
}
