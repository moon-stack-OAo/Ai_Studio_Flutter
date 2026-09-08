import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';

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
    this.onReload,
    this.isReloading,
    this.onSaveAlbum,
    this.onShare,
    this.emptyHint = '还没有视频任务',
    this.emptySubtitle = '在上方填写提示词后创建任务。',
  });

  final List<VideoItem> items;
  final void Function(VideoItem item) onOpen;
  final void Function(VideoItem item) onSave;
  final void Function(VideoItem item) onResume;
  final void Function(VideoItem item) onAbandon;
  final void Function(VideoItem item)? onPlay;
  final void Function(VideoItem item)? onReload;
  final bool Function(VideoItem item)? isReloading;
  final void Function(VideoItem item)? onSaveAlbum;
  final void Function(VideoItem item)? onShare;
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
                onReload: widget.onReload,
                isReloading: widget.isReloading,
                onSaveAlbum: widget.onSaveAlbum,
                onShare: widget.onShare,
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
    this.onReload,
    this.isReloading,
    this.onSaveAlbum,
    this.onShare,
  });

  final VideoItem item;
  final int turnIndex;
  final void Function(VideoItem item) onOpen;
  final void Function(VideoItem item) onSave;
  final void Function(VideoItem item) onResume;
  final void Function(VideoItem item) onAbandon;
  final void Function(VideoItem item)? onPlay;
  final void Function(VideoItem item)? onReload;
  final bool Function(VideoItem item)? isReloading;
  final void Function(VideoItem item)? onSaveAlbum;
  final void Function(VideoItem item)? onShare;

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
        Container(
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
                '你 · 回合 $turnIndex · ${_timeLabel(item.createdAt)}'
                '${item.mode == VideoGenMode.image ? ' · 图生视频' : ' · 文生视频'}'
                '${item.duration != null ? ' · ${item.duration}s' : ''}',
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
            ],
          ),
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

  List<Widget> _actions(MaterialTokens tokens) {
    final reloadBtn = _canReload
        ? TextButton(
            onPressed: () => onReload!(item),
            child: Text(
              isReloading?.call(item) == true ? '加载中…' : '重新加载',
            ),
          )
        : null;

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
        ];
      case VideoItemStatus.abandoned:
        return const [];
    }
  }
}
