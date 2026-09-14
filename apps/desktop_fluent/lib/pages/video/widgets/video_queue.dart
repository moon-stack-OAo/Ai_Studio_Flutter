import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../../../widgets/collapsible_prompt.dart';
import '../../../widgets/empty_illustrations.dart';
import '../../../widgets/fluent_empty_states.dart';

/// F-VideoQueue：time-split + prompt-mini + 任务卡。
class VideoQueue extends StatefulWidget {
  const VideoQueue({
    super.key,
    required this.items,
    required this.onOpen,
    required this.onSave,
    required this.onResume,
    required this.onAbandon,
    this.onPlay,
    this.onSelect,
    this.onRerun,
    this.rerunEnabled = true,
    this.selectedId,
    this.onReload,
    this.isReloading,
    this.posterService,
    this.onPosterCached,
    this.loadReferenceBytes,
    this.onPreviewReference,
    this.emptyHint = '还没有视频任务',
    this.emptySubtitle =
        '在右侧填写提示词与参数后创建；恢复未完成走命令栏。',
  });

  final List<VideoItem> items;
  final void Function(VideoItem item) onOpen;
  final void Function(VideoItem item) onSave;
  final void Function(VideoItem item) onResume;
  final void Function(VideoItem item) onAbandon;
  final void Function(VideoItem item)? onPlay;
  final void Function(VideoItem item)? onSelect;
  /// `VID-RERUN`：用此提示重跑（回填 Composer）。
  final void Function(VideoItem item)? onRerun;
  final bool rerunEnabled;
  final String? selectedId;
  final void Function(VideoItem item)? onReload;
  final bool Function(VideoItem item)? isReloading;
  final VideoPosterService? posterService;
  final void Function(VideoItem item, String localPath)? onPosterCached;
  /// 读取本回合参考图像素（`VID-TURN-REF`）。
  final Future<Uint8List?> Function(ImageRef ref)? loadReferenceBytes;
  final void Function(VideoItem item, int index, ImageRef ref)?
      onPreviewReference;
  final String emptyHint;
  final String? emptySubtitle;

  @override
  State<VideoQueue> createState() => _VideoQueueState();
}

class _VideoQueueState extends State<VideoQueue> {
  /// `null` = 全部。
  VideoItemStatus? _statusFilter;

  static const _filters = <(VideoItemStatus?, String)>[
    (null, '全部'),
    (VideoItemStatus.loading, '生成中'),
    (VideoItemStatus.pendingResume, '待恢复'),
    (VideoItemStatus.success, '已完成'),
    (VideoItemStatus.error, '失败'),
    (VideoItemStatus.abandoned, '已放弃'),
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    if (widget.items.isEmpty) {
      return FluentContentEmpty(
        hint: widget.emptyHint,
        subtitle: widget.emptySubtitle,
        illustration: const FluentEmptyIllustration.noVideos(),
      );
    }

    // 最新在上：进页即见最新任务，无需自动滚底。
    final sorted = List<VideoItem>.from(widget.items)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final total = sorted.length;
    final turnById = <String, int>{
      for (var i = 0; i < sorted.length; i++) sorted[i].id: total - i,
    };
    final filtered = _statusFilter == null
        ? sorted
        : sorted.where((e) => e.status == _statusFilter).toList();

    final children = <Widget>[
      _StatusFilterBar(
        tokens: tokens,
        filters: _filters,
        selected: _statusFilter,
        onChanged: (v) => setState(() => _statusFilter = v),
      ),
    ];

    if (filtered.isEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 24),
          child: FluentContentEmpty(
            hint: '当前筛选无任务',
            subtitle: '试试切换其他状态，或选「全部」。',
            illustration: const FluentEmptyIllustration.noVideos(),
          ),
        ),
      );
    } else {
      for (final item in filtered) {
        children.add(
          _TimeSplit(
            label: _formatTimeSplitLabel(item.createdAt),
            tokens: tokens,
          ),
        );
        children.add(
          _TurnBlock(
            item: item,
            turnIndex: turnById[item.id] ?? 0,
            tokens: tokens,
            selected: widget.selectedId == item.id,
            onOpen: widget.onOpen,
            onSave: widget.onSave,
            onResume: widget.onResume,
            onAbandon: widget.onAbandon,
            onPlay: widget.onPlay,
            onSelect: widget.onSelect,
            onRerun: widget.onRerun,
            rerunEnabled: widget.rerunEnabled,
            onReload: widget.onReload,
            isReloading: widget.isReloading,
            posterService: widget.posterService,
            onPosterCached: widget.onPosterCached,
            loadReferenceBytes: widget.loadReferenceBytes,
            onPreviewReference: widget.onPreviewReference,
          ),
        );
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 16),
      children: children,
    );
  }
}

class _StatusFilterBar extends StatelessWidget {
  const _StatusFilterBar({
    required this.tokens,
    required this.filters,
    required this.selected,
    required this.onChanged,
  });

  final FluentTokens tokens;
  final List<(VideoItemStatus?, String)> filters;
  final VideoItemStatus? selected;
  final ValueChanged<VideoItemStatus?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < filters.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              _StatusFilterChip(
                tokens: tokens,
                label: filters[i].$2,
                selected: selected == filters[i].$1,
                onPressed: () => onChanged(filters[i].$1),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusFilterChip extends StatelessWidget {
  const _StatusFilterChip({
    required this.tokens,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final FluentTokens tokens;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '筛选状态：$label',
      excludeSemantics: true,
      child: HoverButton(
        onPressed: onPressed,
        cursor: SystemMouseCursors.click,
        builder: (context, states) {
          final focused = states.isFocused;
          return AnimatedContainer(
            duration: FluentMotion.micro,
            curve: FluentMotion.standard,
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? tokens.primary.withValues(alpha: 0.14)
                  : tokens.surfaceMuted,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: focused
                    ? tokens.primary
                    : selected
                        ? Color.lerp(tokens.primary, tokens.border, 0.5)!
                        : tokens.border,
                width: focused ? 1.5 : 1,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: selected ? tokens.primaryPressed : tokens.inkSecondary,
                fontFamily: tokens.fontFamily,
              ),
            ),
          );
        },
      ),
    );
  }
}

String _formatTimeSplitLabel(int ms) {
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
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 4),
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
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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

class _TurnBlock extends StatelessWidget {
  const _TurnBlock({
    required this.item,
    required this.turnIndex,
    required this.tokens,
    required this.selected,
    required this.onOpen,
    required this.onSave,
    required this.onResume,
    required this.onAbandon,
    this.onPlay,
    this.onSelect,
    this.onRerun,
    this.rerunEnabled = true,
    this.onReload,
    this.isReloading,
    this.posterService,
    this.onPosterCached,
    this.loadReferenceBytes,
    this.onPreviewReference,
  });

  final VideoItem item;
  final int turnIndex;
  final FluentTokens tokens;
  final bool selected;
  final void Function(VideoItem item) onOpen;
  final void Function(VideoItem item) onSave;
  final void Function(VideoItem item) onResume;
  final void Function(VideoItem item) onAbandon;
  final void Function(VideoItem item)? onPlay;
  final void Function(VideoItem item)? onSelect;
  final void Function(VideoItem item)? onRerun;
  final bool rerunEnabled;
  final void Function(VideoItem item)? onReload;
  final bool Function(VideoItem item)? isReloading;
  final Future<Uint8List?> Function(ImageRef ref)? loadReferenceBytes;
  final void Function(VideoItem item, int index, ImageRef ref)?
      onPreviewReference;
  final VideoPosterService? posterService;
  final void Function(VideoItem item, String localPath)? onPosterCached;

  bool get _canPlay {
    if (onPlay == null) return false;
    if (item.status != VideoItemStatus.success) return false;
    final path = item.localPath ?? item.videoUrl ?? item.remoteVideoUrl;
    return isPlayableVideoPath(path) &&
        !(path ?? '').startsWith('memory://');
  }

  bool get _canReload {
    if (onReload == null) return false;
    if (isReloading?.call(item) == true) return false;
    if (item.needsMaterialize) return true;
    final remote = (item.remoteVideoUrl ?? '').trim();
    final hasRemote =
        RegExp(r'^https?://', caseSensitive: false).hasMatch(remote);
    return item.status == VideoItemStatus.error &&
        (hasRemote || (item.jobId?.isNotEmpty == true));
  }

  String _statusLabel() {
    switch (item.status) {
      case VideoItemStatus.loading:
        final p = item.progress;
        if (p != null) return 'running ${p.round()}%';
        return 'running';
      case VideoItemStatus.pendingResume:
        return 'pending_resume';
      case VideoItemStatus.success:
        return 'succeeded';
      case VideoItemStatus.error:
        return 'failed';
      case VideoItemStatus.abandoned:
        return 'abandoned';
    }
  }

  Color _pillColor() {
    switch (item.status) {
      case VideoItemStatus.loading:
        return tokens.primary;
      case VideoItemStatus.pendingResume:
        return tokens.warning;
      case VideoItemStatus.success:
        return tokens.success;
      case VideoItemStatus.error:
        return tokens.danger;
      case VideoItemStatus.abandoned:
        return tokens.inkMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress =
        ((item.progress ?? 0).clamp(0, 100) / 100.0).toDouble();
    final title = item.prompt.trim().isEmpty
        ? '视频任务'
        : (item.prompt.trim().length <= 28
            ? item.prompt.trim()
            : '${item.prompt.trim().substring(0, 28)}…');

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _UserPromptBubble(
            prompt: item.prompt,
            tokens: tokens,
            header:
                '你 · 回合 $turnIndex'
                '${item.mode == VideoGenMode.image ? ' · 图生视频' : ''}'
                '${item.duration != null ? ' · ${item.duration}s' : ''}',
            referenceImages: item.referenceImages,
            loadBytes: loadReferenceBytes,
            onPreviewReference: onPreviewReference == null
                ? null
                : (index, ref) => onPreviewReference!(item, index, ref),
          ),
          const SizedBox(height: 8),
          Opacity(
            opacity: item.status == VideoItemStatus.abandoned ? 0.72 : 1,
            child: Semantics(
              button: item.status == VideoItemStatus.success,
              selected: selected,
              label:
                  '视频回合 $turnIndex，$title，状态 ${_statusLabelZh()}，${_metaLine()}',
              child: GestureDetector(
                onTap: () {
                  if (item.status == VideoItemStatus.success) {
                    (onSelect ?? onPlay)?.call(item);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  decoration: BoxDecoration(
                    color: tokens.surfaceMuted,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected
                          ? Color.lerp(tokens.primary, tokens.border, 0.55)!
                          : item.status == VideoItemStatus.loading
                              ? Color.lerp(tokens.primary, tokens.border, 0.55)!
                              : tokens.border,
                    ),
                    boxShadow: item.status == VideoItemStatus.loading
                        ? [
                            BoxShadow(
                              color: tokens.primary.withValues(alpha: 0.12),
                              blurRadius: 0,
                              spreadRadius: 3,
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (item.status == VideoItemStatus.success) ...[
                            _QueuePosterThumb(
                              item: item,
                              tokens: tokens,
                              posterService: posterService,
                              onPosterCached: onPosterCached,
                              canPlay: _canPlay,
                              onPlay: () {
                                if (_canPlay) {
                                  (onSelect ?? onPlay)?.call(item);
                                }
                              },
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: tokens.ink,
                                    fontFamily: tokens.fontFamily,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _metaLine(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: tokens.inkMuted,
                                    fontFamily: tokens.fontFamily,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: _pillColor().withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: _pillColor().withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              _statusLabel(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: _pillColor(),
                                fontFamily: tokens.fontFamily,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (item.status == VideoItemStatus.loading) ...[
                        const SizedBox(height: 10),
                        ProgressBar(
                          value: item.progress == null ? null : progress * 100,
                        ),
                      ],
                      if (item.status == VideoItemStatus.error ||
                          item.status == VideoItemStatus.pendingResume ||
                          item.status == VideoItemStatus.abandoned ||
                          item.needsMaterialize)
                        if ((item.errorMessage ?? '').isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            item.errorMessage!,
                            style: TextStyle(
                              fontSize: 12,
                              color: item.status == VideoItemStatus.error ||
                                      item.needsMaterialize
                                  ? tokens.danger
                                  : tokens.inkSecondary,
                              fontFamily: tokens.fontFamily,
                            ),
                          ),
                        ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: _actions(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabelZh() {
    switch (item.status) {
      case VideoItemStatus.loading:
        final p = item.progress;
        if (p != null) return '生成中 ${p.round()}%';
        return '生成中';
      case VideoItemStatus.pendingResume:
        return '待恢复';
      case VideoItemStatus.success:
        return '已完成';
      case VideoItemStatus.error:
        return '失败';
      case VideoItemStatus.abandoned:
        return '已放弃';
    }
  }

  String _metaLine() {
    switch (item.status) {
      case VideoItemStatus.loading:
        return item.jobId?.isNotEmpty == true
            ? '轮询中 · ${item.jobId}'
            : '提交中…';
      case VideoItemStatus.pendingResume:
        return '可恢复轮询';
      case VideoItemStatus.success:
        return item.needsMaterialize ? '需重新加载' : '完成 · 可播放 / 另存';
      case VideoItemStatus.error:
        return item.needsMaterialize
            ? '已生成 · 可重新加载'
            : '失败 · 可重试参数或检查配置';
      case VideoItemStatus.abandoned:
        return '已放弃';
    }
  }

  Widget? _rerunBtn() {
    if (onRerun == null) return null;
    if (item.prompt.trim().isEmpty && item.referenceImages.isEmpty) {
      return null;
    }
    return Button(
      onPressed: rerunEnabled ? () => onRerun!(item) : null,
      child: const Text('用此提示重跑'),
    );
  }

  List<Widget> _actions() {
    final reloadBtn = _canReload
        ? Button(
            onPressed: () => onReload!(item),
            child: Text(
              isReloading?.call(item) == true ? '加载中…' : '重新加载',
            ),
          )
        : null;
    final rerunBtn = _rerunBtn();

    switch (item.status) {
      case VideoItemStatus.loading:
        return const [];
      case VideoItemStatus.pendingResume:
        return [
          Button(
            onPressed: () => onResume(item),
            child: const Text('恢复'),
          ),
          Button(
            onPressed: () => onAbandon(item),
            child: const Text('放弃'),
          ),
          ?rerunBtn,
        ];
      case VideoItemStatus.success:
        return [
          ?reloadBtn,
          if (_canPlay)
            Button(
              onPressed: () => onPlay!(item),
              child: const Text('在右侧播放'),
            ),
          Button(
            onPressed: () => onOpen(item),
            child: const Text('系统打开'),
          ),
          Button(
            onPressed: () => onSave(item),
            child: const Text('另存为'),
          ),
          ?rerunBtn,
        ];
      case VideoItemStatus.error:
        return [
          ?reloadBtn,
          if (!item.needsMaterialize && item.jobId?.isNotEmpty == true)
            Button(
              onPressed: () => onResume(item),
              child: const Text('恢复'),
            ),
          Button(
            onPressed: () => onAbandon(item),
            child: const Text('放弃'),
          ),
          ?rerunBtn,
        ];
      case VideoItemStatus.abandoned:
        return [
          ?rerunBtn,
        ];
    }
  }
}

/// VID-QUEUE 成功项封面：posterUrl → 本地抽帧 → 占位；点击等价播放。
class _QueuePosterThumb extends StatefulWidget {
  const _QueuePosterThumb({
    required this.item,
    required this.tokens,
    required this.canPlay,
    required this.onPlay,
    this.posterService,
    this.onPosterCached,
  });

  final VideoItem item;
  final FluentTokens tokens;
  final bool canPlay;
  final VoidCallback onPlay;
  final VideoPosterService? posterService;
  final void Function(VideoItem item, String localPath)? onPosterCached;

  @override
  State<_QueuePosterThumb> createState() => _QueuePosterThumbState();
}

class _QueuePosterThumbState extends State<_QueuePosterThumb> {
  String? _path;
  bool _failed = false;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void didUpdateWidget(covariant _QueuePosterThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.item.posterUrl != widget.item.posterUrl ||
        oldWidget.item.posterLocalPath != widget.item.posterLocalPath ||
        oldWidget.item.localPath != widget.item.localPath ||
        oldWidget.item.videoUrl != widget.item.videoUrl) {
      _bootstrap();
    }
  }

  void _bootstrap() {
    final service = widget.posterService;
    final peeked = service?.peekPoster(widget.item);
    _path = peeked;
    _failed = false;
    _token++;
    final token = _token;
    if (service == null) return;
    if (VideoPosterService.isRemotePosterUrl(peeked)) return;
    unawaited(_resolve(service, token));
  }

  Future<void> _resolve(VideoPosterService service, int token) async {
    final resolved = await service.resolvePoster(widget.item);
    if (!mounted || token != _token) return;
    if (resolved == null || resolved.isEmpty) {
      setState(() {
        _path = null;
        _failed = true;
      });
      return;
    }
    setState(() {
      _path = resolved;
      _failed = false;
    });
    final isRemote = VideoPosterService.isRemotePosterUrl(resolved);
    if (!isRemote &&
        resolved != widget.item.posterLocalPath &&
        !resolved.startsWith('memory-poster://')) {
      widget.onPosterCached?.call(widget.item, resolved);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.canPlay ? widget.onPlay : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 72,
          height: 40,
          color: tokens.surface,
          foregroundDecoration: BoxDecoration(
            border: Border.all(color: tokens.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildImage(tokens),
              if (widget.canPlay)
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: const Color(0xFF000000).withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      FluentIcons.play,
                      size: 10,
                      color: Color(0xFFFFFFFF),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImage(FluentTokens tokens) {
    final path = _path;
    if (_failed || path == null || path.isEmpty) {
      return _placeholder(tokens);
    }
    if (VideoPosterService.isRemotePosterUrl(path)) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(tokens),
      );
    }
    if (path.startsWith('memory-poster://')) {
      return _placeholder(tokens);
    }
    final file = File(path);
    if (!file.existsSync()) return _placeholder(tokens);
    return Image.file(
      file,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => _placeholder(tokens),
    );
  }

  Widget _placeholder(FluentTokens tokens) {
    return ColoredBox(
      color: tokens.surfaceMuted,
      child: Icon(
        FluentIcons.video,
        size: 16,
        color: tokens.inkMuted,
      ),
    );
  }
}

class _UserPromptBubble extends StatefulWidget {
  const _UserPromptBubble({
    required this.prompt,
    required this.tokens,
    required this.header,
    this.referenceImages = const [],
    this.loadBytes,
    this.onPreviewReference,
  });

  final String prompt;
  final FluentTokens tokens;
  final String header;
  final List<ImageRef> referenceImages;
  final Future<Uint8List?> Function(ImageRef ref)? loadBytes;
  final void Function(int index, ImageRef ref)? onPreviewReference;

  @override
  State<_UserPromptBubble> createState() => _UserPromptBubbleState();
}

class _UserPromptBubbleState extends State<_UserPromptBubble> {
  final FlyoutController _flyout = FlyoutController();
  bool _hovered = false;

  @override
  void dispose() {
    _flyout.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    final text = widget.prompt;
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    displayInfoBar(
      context,
      builder: (context, close) {
        return InfoBar(
          title: const Text('已复制'),
          severity: InfoBarSeverity.success,
          onClose: close,
        );
      },
    );
  }

  Future<void> _showContextMenu(Offset globalPosition) async {
    final navBox =
        Navigator.of(context).context.findRenderObject() as RenderBox?;
    if (navBox == null) return;
    final position = navBox.globalToLocal(globalPosition);
    await _flyout.showFlyout<void>(
      position: position,
      barrierDismissible: true,
      dismissWithEsc: true,
      builder: (ctx) {
        return MenuFlyout(
          items: [
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.copy, size: 14),
              text: const Text('复制'),
              onPressed: () {
                Navigator.of(ctx).pop();
                _copy();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: FlyoutTarget(
        controller: _flyout,
        child: GestureDetector(
          onSecondaryTapUp: (details) =>
              _showContextMenu(details.globalPosition),
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
                  widget.header,
                  style: TextStyle(
                    fontSize: 11,
                    color: tokens.inkMuted,
                    fontFamily: tokens.fontFamily,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.referenceImages.isNotEmpty) ...[
                      _TurnRefThumbs(
                        refs: widget.referenceImages,
                        tokens: tokens,
                        loadBytes: widget.loadBytes,
                        onTap: widget.onPreviewReference,
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: CollapsiblePrompt(
                        text: widget.prompt,
                        maxLines: 3,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.55,
                          color: tokens.inkSecondary,
                          fontFamily: tokens.fontFamily,
                        ),
                        linkColor: tokens.primary,
                      ),
                    ),
                  ],
                ),
                AnimatedOpacity(
                  opacity: _hovered ? 1 : 0,
                  duration: FluentMotion.micro,
                  curve: FluentMotion.standard,
                  child: IgnorePointer(
                    ignoring: !_hovered,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: _PromptCopyChip(
                        onPressed: _copy,
                        tokens: tokens,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 视频回合参考图缩略（`VID-TURN-REF`）。
class _TurnRefThumbs extends StatelessWidget {
  const _TurnRefThumbs({
    required this.refs,
    required this.tokens,
    this.loadBytes,
    this.onTap,
  });

  final List<ImageRef> refs;
  final FluentTokens tokens;
  final Future<Uint8List?> Function(ImageRef ref)? loadBytes;
  final void Function(int index, ImageRef ref)? onTap;

  static const double _size = 52;

  @override
  Widget build(BuildContext context) {
    final shown = refs.length > maxTurnReferenceImages
        ? refs.sublist(0, maxTurnReferenceImages)
        : refs;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < shown.length; index++) ...[
          if (index > 0) const SizedBox(width: 6),
          Builder(
            builder: (context) {
              final ref = shown[index];
              return Semantics(
                button: onTap != null,
                label: '参考图 ${index + 1}',
                child: GestureDetector(
                  onTap: onTap == null ? null : () => onTap!(index, ref),
                  child: MouseRegion(
                    cursor: onTap == null
                        ? SystemMouseCursors.basic
                        : SystemMouseCursors.click,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: _size,
                        height: _size,
                        decoration: BoxDecoration(
                          color: tokens.surface,
                          border: Border.all(color: tokens.border),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: _TurnRefThumb(ref: ref, loadBytes: loadBytes),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

class _TurnRefThumb extends StatefulWidget {
  const _TurnRefThumb({required this.ref, this.loadBytes});

  final ImageRef ref;
  final Future<Uint8List?> Function(ImageRef ref)? loadBytes;

  @override
  State<_TurnRefThumb> createState() => _TurnRefThumbState();
}

class _TurnRefThumbState extends State<_TurnRefThumb> {
  Uint8List? _bytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _TurnRefThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ref.src != widget.ref.src ||
        oldWidget.ref.type != widget.ref.type) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _bytes = null;
    });
    try {
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
      final loader = widget.loadBytes;
      if (loader != null) {
        final b = await loader(widget.ref);
        if (mounted) {
          setState(() {
            _bytes = b;
            _loading = false;
          });
        }
        return;
      }
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: ProgressRing(strokeWidth: 2));
    }
    if (_bytes != null && _bytes!.isNotEmpty) {
      return Image.memory(_bytes!, fit: BoxFit.cover);
    }
    if (widget.ref.type == ImageRefType.url) {
      return Image.network(
        widget.ref.src,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            const Center(child: Icon(FluentIcons.photo, size: 16)),
      );
    }
    return const Center(child: Icon(FluentIcons.photo, size: 16));
  }
}

class _PromptCopyChip extends StatelessWidget {
  const _PromptCopyChip({
    required this.onPressed,
    required this.tokens,
  });

  final VoidCallback onPressed;
  final FluentTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '复制',
      excludeSemantics: true,
      child: HoverButton(
        onPressed: onPressed,
        cursor: SystemMouseCursors.click,
        builder: (context, states) {
          final hovered = states.isHovered || states.isPressed;
          return Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: hovered ? tokens.surfaceMuted : tokens.surface,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: tokens.border),
            ),
            alignment: Alignment.center,
            child: Text(
              '复制',
              style: TextStyle(
                fontSize: 11,
                color: hovered ? tokens.ink : tokens.inkSecondary,
                fontFamily: tokens.fontFamily,
              ),
            ),
          );
        },
      ),
    );
  }
}
