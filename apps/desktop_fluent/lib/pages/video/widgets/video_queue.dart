import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../../widgets/collapsible_prompt.dart';
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
    this.selectedId,
    this.onReload,
    this.isReloading,
    this.emptyHint = '输入提示词创建视频任务',
    this.emptySubtitle = '在右侧参数区填写提示词后创建任务。',
  });

  final List<VideoItem> items;
  final void Function(VideoItem item) onOpen;
  final void Function(VideoItem item) onSave;
  final void Function(VideoItem item) onResume;
  final void Function(VideoItem item) onAbandon;
  final void Function(VideoItem item)? onPlay;
  final void Function(VideoItem item)? onSelect;
  final String? selectedId;
  final void Function(VideoItem item)? onReload;
  final bool Function(VideoItem item)? isReloading;
  final String emptyHint;
  final String? emptySubtitle;

  @override
  State<VideoQueue> createState() => _VideoQueueState();
}

class _VideoQueueState extends State<VideoQueue> {
  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    if (widget.items.isEmpty) {
      return FluentContentEmpty(
        hint: widget.emptyHint,
        subtitle: widget.emptySubtitle,
      );
    }

    // 最新在上：进页即见最新任务，无需自动滚底。
    final sorted = List<VideoItem>.from(widget.items)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final total = sorted.length;

    final children = <Widget>[];
    for (var i = 0; i < sorted.length; i++) {
      final item = sorted[i];
      children.add(
        _TimeSplit(label: _formatTimeSplitLabel(item.createdAt), tokens: tokens),
      );
      children.add(
        _TurnBlock(
          item: item,
          turnIndex: total - i,
          tokens: tokens,
          selected: widget.selectedId == item.id,
          onOpen: widget.onOpen,
          onSave: widget.onSave,
          onResume: widget.onResume,
          onAbandon: widget.onAbandon,
          onPlay: widget.onPlay,
          onSelect: widget.onSelect,
          onReload: widget.onReload,
          isReloading: widget.isReloading,
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 16),
      children: children,
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
    this.onReload,
    this.isReloading,
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
  final void Function(VideoItem item)? onReload;
  final bool Function(VideoItem item)? isReloading;

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
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: tokens.canvas,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: tokens.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '你 · 回合 $turnIndex'
                  '${item.mode == VideoGenMode.image ? ' · 图生视频' : ''}'
                  '${item.duration != null ? ' · ${item.duration}s' : ''}',
                  style: TextStyle(
                    fontSize: 10,
                    color: tokens.inkMuted,
                    fontFamily: tokens.fontFamily,
                  ),
                ),
                const SizedBox(height: 4),
                CollapsiblePrompt(
                  text: item.prompt,
                  maxLines: 3,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: tokens.inkSecondary,
                    fontFamily: tokens.fontFamily,
                  ),
                  linkColor: tokens.primary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
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
        ],
      ),
    );
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

  List<Widget> _actions() {
    final reloadBtn = _canReload
        ? Button(
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
          Button(
            onPressed: () => onResume(item),
            child: const Text('恢复'),
          ),
          Button(
            onPressed: () => onAbandon(item),
            child: const Text('放弃'),
          ),
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
        ];
      case VideoItemStatus.abandoned:
        return const [];
    }
  }
}
