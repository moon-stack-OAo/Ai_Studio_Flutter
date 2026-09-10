import 'dart:io';

import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:video_player/video_player.dart';

import 'video_playback_guard.dart';
import 'video_player_dialog.dart' show resolveVideoItemPlayablePath;

/// F-VideoPlayer · VID-PLAYER：主区内嵌播放面板。
class VideoPlayerPanel extends StatelessWidget {
  const VideoPlayerPanel({
    super.key,
    required this.item,
    required this.onOpenSystem,
    required this.onSaveAs,
    this.onExpand,
  });

  final VideoItem? item;
  final Future<bool> Function(VideoItem item) onOpenSystem;
  final Future<bool> Function(VideoItem item) onSaveAs;
  final VoidCallback? onExpand;

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: tokens.border)),
            ),
            child: Row(
              children: [
                Text(
                  '播放器',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: tokens.ink,
                    fontFamily: tokens.fontFamily,
                  ),
                ),
                const Spacer(),
                Text(
                  _stageLabel(item),
                  style: TextStyle(
                    fontSize: 11,
                    color: tokens.inkMuted,
                    fontFamily: tokens.fontFamily,
                  ),
                ),
                if (item != null && onExpand != null) ...[
                  const SizedBox(width: 8),
                  HyperlinkButton(
                    onPressed: onExpand,
                    child: const Text('放大'),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: item == null
                ? _EmptyStage(tokens: tokens)
                : _InlinePlayer(
                    key: ValueKey(item!.id),
                    item: item!,
                    tokens: tokens,
                    onOpenSystem: onOpenSystem,
                    onSaveAs: onSaveAs,
                  ),
          ),
        ],
      ),
    );
  }
}

String _stageLabel(VideoItem? item) {
  final raw = item?.aspectRatio?.trim();
  if (raw != null && raw.isNotEmpty) return '$raw 舞台';
  return '自适应舞台';
}

double? parseVideoAspectRatio(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty) return null;
  final parts = s.split(':');
  if (parts.length != 2) return null;
  final w = double.tryParse(parts[0].trim());
  final h = double.tryParse(parts[1].trim());
  if (w == null || h == null || w <= 0 || h <= 0) return null;
  return w / h;
}

class _EmptyStage extends StatelessWidget {
  const _EmptyStage({required this.tokens});

  final FluentTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: tokens.border),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF0F1115),
                    Color.lerp(tokens.primary, const Color(0xFF12151C), 0.85)!,
                    const Color(0xFF12151C),
                  ],
                ),
              ),
              child: Center(
                child: Text(
                  '从左侧队列选择已完成任务播放',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.65),
                    fontFamily: tokens.fontFamily,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '杀进程后可经「恢复未完成」继续轮询；进度态与生图时间线信息架构不同。',
            style: TextStyle(
              fontSize: 11,
              height: 1.5,
              color: tokens.inkMuted,
              fontFamily: tokens.fontFamily,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlinePlayer extends StatefulWidget {
  const _InlinePlayer({
    super.key,
    required this.item,
    required this.tokens,
    required this.onOpenSystem,
    required this.onSaveAs,
  });

  final VideoItem item;
  final FluentTokens tokens;
  final Future<bool> Function(VideoItem item) onOpenSystem;
  final Future<bool> Function(VideoItem item) onSaveAs;

  @override
  State<_InlinePlayer> createState() => _InlinePlayerState();
}

class _InlinePlayerState extends State<_InlinePlayer> {
  VideoPlayerController? _controller;
  VideoPlaybackGuard? _guard;
  String? _error;
  bool _ready = false;
  String? _boundItemId;
  String? _boundPath;
  int _bindToken = 0;

  @override
  void initState() {
    super.initState();
    _bind(widget.item, force: true);
  }

  @override
  void didUpdateWidget(covariant _InlinePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bind(widget.item);
  }

  bool _shouldRebind(VideoItem item) {
    if (_boundItemId != item.id) return true;
    final next = resolveVideoItemPlayablePath(item);
    if (_boundPath == next) return false;
    if (next == null || next.isEmpty) return false;
    if (_ready && _controller != null && _controller!.value.isInitialized) {
      final upgradingToLocal = _isHttp(_boundPath) && !_isHttp(next);
      if (upgradingToLocal) return false;
    }
    return true;
  }

  bool _isHttp(String? path) {
    final s = (path ?? '').trim();
    return RegExp(r'^https?://', caseSensitive: false).hasMatch(s);
  }

  Future<void> _bind(VideoItem item, {bool force = false}) async {
    if (!force && !_shouldRebind(item)) {
      return;
    }

    final path = resolveVideoItemPlayablePath(item);
    final token = ++_bindToken;
    final old = _controller;
    final oldGuard = _guard;
    _controller = null;
    _guard = null;
    _boundItemId = item.id;
    _boundPath = path;
    if (mounted) {
      setState(() {
        _ready = false;
        _error = null;
      });
    }
    oldGuard?.dispose();
    await old?.dispose();
    if (!mounted || token != _bindToken) return;

    if (path == null || path.isEmpty) {
      if (mounted && token == _bindToken) {
        setState(() => _error = '没有可播放的视频地址');
      }
      return;
    }
    if (path.startsWith('memory://')) {
      if (mounted && token == _bindToken) {
        setState(() => _error = '内存视频请先另存或系统打开');
      }
      return;
    }
    try {
      final VideoPlayerController ctrl;
      if (_isHttp(path)) {
        ctrl = VideoPlayerController.networkUrl(Uri.parse(path));
      } else {
        final filePath =
            path.startsWith('file:') ? Uri.parse(path).toFilePath() : path;
        final f = File(filePath);
        if (!await f.exists()) {
          if (mounted && token == _bindToken) {
            setState(() => _error = '本地文件不存在');
          }
          return;
        }
        ctrl = VideoPlayerController.file(f);
      }
      if (!mounted || token != _bindToken) {
        await ctrl.dispose();
        return;
      }
      _controller = ctrl;
      await ctrl.initialize();
      if (!mounted || token != _bindToken) {
        await ctrl.dispose();
        return;
      }
      await ctrl.setLooping(false);
      if (!mounted || token != _bindToken) {
        await ctrl.dispose();
        return;
      }
      final guard = VideoPlaybackGuard(ctrl);
      _guard = guard;
      setState(() => _ready = true);
      // 先起墙钟再 await play，避免开头长时间停在 0。
      guard.notePlayStarted();
      await ctrl.play();
    } catch (e) {
      if (!mounted || token != _bindToken) return;
      setState(() => _error = '播放器初始化失败：$e');
    }
  }

  @override
  void dispose() {
    _bindToken++;
    final g = _guard;
    final c = _controller;
    _guard = null;
    _controller = null;
    g?.dispose();
    c?.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  double _stageAspectRatio() {
    final ctrl = _controller;
    if (_ready && ctrl != null && ctrl.value.isInitialized) {
      final ar = ctrl.value.aspectRatio;
      if (ar > 0) return ar;
    }
    return parseVideoAspectRatio(widget.item.aspectRatio) ?? (16 / 9);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: _stageAspectRatio(),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF0F1115),
                borderRadius: BorderRadius.circular(10),
              ),
              child: _buildStage(tokens),
            ),
          ),
          if (_ready && _controller != null && _guard != null) ...[
            const SizedBox(height: 10),
            _Transport(
              controller: _controller!,
              guard: _guard!,
              tokens: tokens,
              fmt: _fmt,
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Button(
                onPressed: () => widget.onSaveAs(widget.item),
                child: const Text('另存为…'),
              ),
              Button(
                onPressed: () => widget.onOpenSystem(widget.item),
                child: const Text('系统打开'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStage(FluentTokens tokens) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: tokens.danger,
              fontFamily: tokens.fontFamily,
              fontSize: 12,
            ),
          ),
        ),
      );
    }
    if (!_ready || _controller == null) {
      return const Center(child: ProgressRing());
    }
    return VideoPlayer(_controller!);
  }
}

class _Transport extends StatelessWidget {
  const _Transport({
    required this.controller,
    required this.guard,
    required this.tokens,
    required this.fmt,
  });

  final VideoPlayerController controller;
  final VideoPlaybackGuard guard;
  final FluentTokens tokens;
  final String Function(Duration) fmt;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([controller, guard]),
      builder: (context, _) {
        final value = controller.value;
        final playing = guard.uiPlaying;
        final position = guard.displayPosition(value);
        return Row(
          children: [
            Tooltip(
              message: playing ? '暂停' : '播放',
              child: Semantics(
                button: true,
                label: playing ? '暂停' : '播放',
                excludeSemantics: true,
                child: IconButton(
                  icon: Icon(
                    playing ? FluentIcons.pause : FluentIcons.play,
                    size: 14,
                  ),
                  onPressed: () => guard.togglePlayPause(),
                ),
              ),
            ),
            Expanded(
              child: _GuardedScrubber(
                controller: controller,
                guard: guard,
                playedColor: tokens.primary,
                bufferedColor: tokens.primary.withValues(alpha: 0.25),
                backgroundColor: tokens.surfaceMuted,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${fmt(position)} / ${fmt(value.duration)}',
              style: TextStyle(
                fontSize: 11,
                color: tokens.inkMuted,
                fontFamily: tokens.fontFamily,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GuardedScrubber extends StatefulWidget {
  const _GuardedScrubber({
    required this.controller,
    required this.guard,
    required this.playedColor,
    required this.bufferedColor,
    required this.backgroundColor,
  });

  final VideoPlayerController controller;
  final VideoPlaybackGuard guard;
  final Color playedColor;
  final Color bufferedColor;
  final Color backgroundColor;

  @override
  State<_GuardedScrubber> createState() => _GuardedScrubberState();
}

class _GuardedScrubberState extends State<_GuardedScrubber> {
  double? _dragFraction;
  bool _wasPlaying = false;

  double _fractionOf(Offset globalPosition) {
    final box = context.findRenderObject()! as RenderBox;
    final local = box.globalToLocal(globalPosition);
    if (box.size.width <= 0) return 0;
    return (local.dx / box.size.width).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.controller, widget.guard]),
      builder: (context, _) {
        final value = widget.controller.value;
        final fraction =
            _dragFraction ?? widget.guard.progressFraction(value);
        final durationMs = value.duration.inMilliseconds;
        final buffered = durationMs <= 0
            ? 0.0
            : value.buffered
                    .map((r) => r.end.inMilliseconds)
                    .fold<int>(0, (a, b) => a > b ? a : b) /
                durationMs;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) {
            _wasPlaying = widget.guard.uiPlaying;
            setState(() => _dragFraction = fraction);
          },
          onHorizontalDragUpdate: (details) {
            setState(() => _dragFraction = _fractionOf(details.globalPosition));
          },
          onHorizontalDragEnd: (_) async {
            final f = _dragFraction ?? fraction;
            setState(() => _dragFraction = null);
            await widget.guard.seekFraction(f, resume: _wasPlaying);
          },
          onTapDown: (details) async {
            final f = _fractionOf(details.globalPosition);
            await widget.guard.seekFraction(
              f,
              resume: widget.guard.uiPlaying,
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              height: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: widget.backgroundColor),
                    FractionallySizedBox(
                      widthFactor: buffered.clamp(0.0, 1.0),
                      alignment: Alignment.centerLeft,
                      child: ColoredBox(color: widget.bufferedColor),
                    ),
                    FractionallySizedBox(
                      widthFactor: fraction.clamp(0.0, 1.0),
                      alignment: Alignment.centerLeft,
                      child: ColoredBox(color: widget.playedColor),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
