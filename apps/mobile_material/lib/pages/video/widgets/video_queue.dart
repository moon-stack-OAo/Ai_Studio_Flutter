import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../widgets/collapsible_prompt.dart';
import '../../../widgets/empty_illustrations.dart';
import '../../../widgets/material_empty_states.dart';

/// M-VideoQueue：按回合时间分隔 — 提示词 + 任务卡 + 进度。
class VideoQueue extends StatefulWidget {
  const VideoQueue({
    super.key,
    required this.items,
    required this.onOpen,
    required this.onSave,
    required this.onResume,
    required this.onAbandon,
    this.onPlay,
    this.onRerun,
    this.rerunEnabled = true,
    this.onReload,
    this.isReloading,
    this.onSaveAlbum,
    this.onShare,
    this.posterService,
    this.onPosterCached,
    this.loadReferenceBytes,
    this.onPreviewReference,
    this.emptyHint = '还没有视频任务',
    this.emptySubtitle = '在上方填写提示词后创建任务。',
  });

  final List<VideoItem> items;
  final void Function(VideoItem item) onOpen;
  final void Function(VideoItem item) onSave;
  final void Function(VideoItem item) onResume;
  final void Function(VideoItem item) onAbandon;
  final void Function(VideoItem item)? onPlay;
  /// `VID-RERUN`：用此提示重跑（回填 Composer）。
  final void Function(VideoItem item)? onRerun;
  final bool rerunEnabled;
  final void Function(VideoItem item)? onReload;
  final bool Function(VideoItem item)? isReloading;
  final void Function(VideoItem item)? onSaveAlbum;
  final void Function(VideoItem item)? onShare;
  final VideoPosterService? posterService;
  final void Function(VideoItem item, String localPath)? onPosterCached;
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
    final tokens = materialTokensOf(context);
    if (widget.items.isEmpty) {
      return MaterialContentEmpty(
        hint: widget.emptyHint,
        subtitle: widget.emptySubtitle,
        illustration: const MaterialEmptyIllustration.noVideos(),
      );
    }

    final sorted = List<VideoItem>.from(widget.items)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final turnById = <String, int>{
      for (var i = 0; i < sorted.length; i++) sorted[i].id: i + 1,
    };
    final filtered = _statusFilter == null
        ? sorted
        : sorted.where((e) => e.status == _statusFilter).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              for (var i = 0; i < _filters.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                FilterChip(
                  label: Text(_filters[i].$2),
                  selected: _statusFilter == _filters[i].$1,
                  showCheckmark: false,
                  onSelected: (_) =>
                      setState(() => _statusFilter = _filters[i].$1),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontFamily: tokens.fontFamily,
                    color: _statusFilter == _filters[i].$1
                        ? tokens.primary
                        : tokens.inkSecondary,
                  ),
                  selectedColor: tokens.primary.withValues(alpha: 0.14),
                  side: BorderSide(
                    color: _statusFilter == _filters[i].$1
                        ? tokens.primary
                        : tokens.border,
                  ),
                  backgroundColor: tokens.surface,
                ),
              ],
            ],
          ),
        ),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: MaterialContentEmpty(
              hint: '当前筛选无任务',
              subtitle: '试试切换其他状态，或选「全部」。',
              illustration: const MaterialEmptyIllustration.noVideos(),
            ),
          )
        else
          for (final item in filtered)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _TurnCard(
                item: item,
                turnIndex: turnById[item.id] ?? 0,
                onOpen: widget.onOpen,
                onSave: widget.onSave,
                onResume: widget.onResume,
                onAbandon: widget.onAbandon,
                onPlay: widget.onPlay,
                onRerun: widget.onRerun,
                rerunEnabled: widget.rerunEnabled,
                onReload: widget.onReload,
                isReloading: widget.isReloading,
                onSaveAlbum: widget.onSaveAlbum,
                onShare: widget.onShare,
                posterService: widget.posterService,
                onPosterCached: widget.onPosterCached,
                loadReferenceBytes: widget.loadReferenceBytes,
                onPreviewReference: widget.onPreviewReference,
              ),
            ),
      ],
    );
  }
}

class _TurnCard extends StatelessWidget {
  const _TurnCard({
    required this.item,
    required this.turnIndex,
    required this.onOpen,
    required this.onSave,
    required this.onResume,
    required this.onAbandon,
    this.onPlay,
    this.onRerun,
    this.rerunEnabled = true,
    this.onReload,
    this.isReloading,
    this.onSaveAlbum,
    this.onShare,
    this.posterService,
    this.onPosterCached,
    this.loadReferenceBytes,
    this.onPreviewReference,
  });

  final VideoItem item;
  final int turnIndex;
  final void Function(VideoItem item) onOpen;
  final void Function(VideoItem item) onSave;
  final void Function(VideoItem item) onResume;
  final void Function(VideoItem item) onAbandon;
  final void Function(VideoItem item)? onPlay;
  final void Function(VideoItem item)? onRerun;
  final bool rerunEnabled;
  final void Function(VideoItem item)? onReload;
  final bool Function(VideoItem item)? isReloading;
  final void Function(VideoItem item)? onSaveAlbum;
  final void Function(VideoItem item)? onShare;
  final VideoPosterService? posterService;
  final void Function(VideoItem item, String localPath)? onPosterCached;
  final Future<Uint8List?> Function(ImageRef ref)? loadReferenceBytes;
  final void Function(VideoItem item, int index, ImageRef ref)?
      onPreviewReference;

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

  String _timeLabel(int ms) {
    if (ms <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
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

  Color _pillColor(MaterialTokens tokens) {
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

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    final progress =
        ((item.progress ?? 0).clamp(0, 100) / 100.0).toDouble();
    final title = item.prompt.trim().isEmpty
        ? '视频任务'
        : (item.prompt.trim().length <= 28
            ? item.prompt.trim()
            : '${item.prompt.trim().substring(0, 28)}…');
    final pill = _pillColor(tokens);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _UserPromptBubble(
          prompt: item.prompt,
          header:
              '你 · 回合 $turnIndex · ${_timeLabel(item.createdAt)}'
              '${item.mode == VideoGenMode.image ? ' · 图生视频' : ' · 文生视频'}'
              '${item.duration != null ? ' · ${item.duration}s' : ''}',
          referenceImages: item.referenceImages,
          loadBytes: loadReferenceBytes,
          onPreviewReference: onPreviewReference == null
              ? null
              : (index, ref) => onPreviewReference!(item, index, ref),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: tokens.border),
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
                        if (_canPlay) onPlay?.call(item);
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
                            fontSize: 14,
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
                      color: pill.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: pill.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      _statusLabel(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: pill,
                        fontFamily: tokens.fontFamily,
                      ),
                    ),
                  ),
                ],
              ),
              if (item.status == VideoItemStatus.loading) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: item.progress == null ? null : progress,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(99),
                  color: tokens.primary,
                  backgroundColor: tokens.surfaceMuted,
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
                spacing: 4,
                runSpacing: 0,
                children: _actions(tokens),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget? _rerunBtn() {
    if (onRerun == null) return null;
    if (item.prompt.trim().isEmpty && item.referenceImages.isEmpty) {
      return null;
    }
    return TextButton(
      onPressed: rerunEnabled ? () => onRerun!(item) : null,
      child: const Text('用此提示重跑'),
    );
  }

  List<Widget> _actions(MaterialTokens tokens) {
    final reloadBtn = _canReload
        ? TextButton(
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
          TextButton(
            onPressed: () => onResume(item),
            child: const Text('恢复'),
          ),
          TextButton(
            onPressed: () => onAbandon(item),
            child: const Text('放弃'),
          ),
          ?rerunBtn,
        ];
      case VideoItemStatus.success:
        return [
          ?reloadBtn,
          if (_canPlay)
            TextButton(
              onPressed: () => onPlay!(item),
              child: const Text('播放'),
            ),
          TextButton(
            onPressed: () => onOpen(item),
            child: const Text('系统打开'),
          ),
          TextButton(
            onPressed: () => onSave(item),
            child: const Text('另存'),
          ),
          TextButton(
            onPressed: onSaveAlbum == null ? null : () => onSaveAlbum!(item),
            child: const Text('存相册'),
          ),
          TextButton(
            onPressed: onShare == null ? null : () => onShare!(item),
            child: const Text('分享'),
          ),
          ?rerunBtn,
        ];
      case VideoItemStatus.error:
        return [
          ?reloadBtn,
          if (!item.needsMaterialize && item.jobId?.isNotEmpty == true)
            TextButton(
              onPressed: () => onResume(item),
              child: const Text('恢复'),
            ),
          TextButton(
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
  final MaterialTokens tokens;
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.canPlay ? widget.onPlay : null,
        borderRadius: BorderRadius.circular(8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 80,
            height: 45,
            color: tokens.surfaceMuted,
            foregroundDecoration: BoxDecoration(
              border: Border.all(color: tokens.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildImage(tokens),
                if (widget.canPlay)
                  const Align(
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.play_circle_fill,
                      size: 22,
                      color: Color(0xCCFFFFFF),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImage(MaterialTokens tokens) {
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

  Widget _placeholder(MaterialTokens tokens) {
    return ColoredBox(
      color: tokens.surfaceMuted,
      child: Icon(
        Icons.videocam_outlined,
        size: 18,
        color: tokens.inkMuted,
      ),
    );
  }
}

class _UserPromptBubble extends StatelessWidget {
  const _UserPromptBubble({
    required this.prompt,
    required this.header,
    this.referenceImages = const [],
    this.loadBytes,
    this.onPreviewReference,
  });

  final String prompt;
  final String header;
  final List<ImageRef> referenceImages;
  final Future<Uint8List?> Function(ImageRef ref)? loadBytes;
  final void Function(int index, ImageRef ref)? onPreviewReference;

  Future<void> _copy(BuildContext context) async {
    if (prompt.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: prompt));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制')),
    );
  }

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
                leading: const Icon(Icons.copy_outlined),
                title: const Text('复制'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _copy(context);
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
    final tokens = materialTokensOf(context);
    return GestureDetector(
      onLongPress: () => _showActions(context),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: tokens.surfaceMuted,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tokens.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              header,
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
                if (referenceImages.isNotEmpty) ...[
                  _TurnRefThumbs(
                    refs: referenceImages,
                    loadBytes: loadBytes,
                    onTap: onPreviewReference,
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: CollapsiblePrompt(
                    text: prompt,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: tokens.ink,
                      fontFamily: tokens.fontFamily,
                    ),
                    linkColor: tokens.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TurnRefThumbs extends StatelessWidget {
  const _TurnRefThumbs({
    required this.refs,
    this.loadBytes,
    this.onTap,
  });

  final List<ImageRef> refs;
  final Future<Uint8List?> Function(ImageRef ref)? loadBytes;
  final void Function(int index, ImageRef ref)? onTap;

  static const double _size = 44;

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    final shown = refs.length > maxTurnReferenceImages
        ? refs.sublist(0, maxTurnReferenceImages)
        : refs;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < shown.length; index++) ...[
          if (index > 0) const SizedBox(width: 8),
          Builder(
            builder: (context) {
              final ref = shown[index];
              return Semantics(
                button: onTap != null,
                label: '参考图 ${index + 1}',
                child: InkWell(
                  onTap: onTap == null ? null : () => onTap!(index, ref),
                  borderRadius: BorderRadius.circular(10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: _size,
                      height: _size,
                      decoration: BoxDecoration(
                        color: tokens.surface,
                        border: Border.all(color: tokens.border),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: _TurnRefThumb(ref: ref, loadBytes: loadBytes),
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
      return const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_bytes != null && _bytes!.isNotEmpty) {
      return Image.memory(_bytes!, fit: BoxFit.cover);
    }
    if (widget.ref.type == ImageRefType.url) {
      return Image.network(
        widget.ref.src,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            const Center(child: Icon(Icons.broken_image_outlined, size: 18)),
      );
    }
    return const Center(child: Icon(Icons.broken_image_outlined, size: 18));
  }
}
