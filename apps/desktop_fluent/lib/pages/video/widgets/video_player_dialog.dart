import 'dart:io';

import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:video_player/video_player.dart';

import 'video_playback_guard.dart';

/// 从 [VideoItem] 解析可播放路径（Dialog / Panel 共用）。
String? resolveVideoItemPlayablePath(VideoItem item) {
  final local = item.localPath?.trim();
  if (local != null && isPlayableVideoPath(local)) return local;
  final url = item.videoUrl?.trim();
  if (url != null && isPlayableVideoPath(url)) return url;
  final remote = item.remoteVideoUrl?.trim();
  if (remote != null && isPlayableVideoPath(remote)) return remote;
  return null;
}

/// F-VideoPlayer：ContentDialog 放大播放，关闭即 dispose。
Future<void> showVideoPlayerDialog(
  BuildContext context, {
  required VideoItem item,
  required Future<bool> Function(VideoItem item) onOpenSystem,
  required Future<bool> Function(VideoItem item) onSaveAs,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      return ContentDialog(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
        title: const Text('播放视频'),
        content: _VideoPlayerBody(item: item),
        actions: [
          Button(
            onPressed: () async {
              await onSaveAs(item);
            },
            child: const Text('另存为'),
          ),
          Button(
            onPressed: () async {
              await onOpenSystem(item);
            },
            child: const Text('系统打开'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      );
    },
  );
}

class _VideoPlayerBody extends StatefulWidget {
  const _VideoPlayerBody({required this.item});

  final VideoItem item;

  @override
  State<_VideoPlayerBody> createState() => _VideoPlayerBodyState();
}

class _VideoPlayerBodyState extends State<_VideoPlayerBody> {
  VideoPlayerController? _controller;
  VideoPlaybackGuard? _guard;
  String? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final path = resolveVideoItemPlayablePath(widget.item);
    if (path == null || path.isEmpty) {
      setState(() => _error = '没有可播放的视频地址');
      return;
    }
    if (path.startsWith('memory://')) {
      setState(() => _error = '内存视频请先另存或系统打开');
      return;
    }
    try {
      final VideoPlayerController ctrl;
      if (RegExp(r'^https?://', caseSensitive: false).hasMatch(path)) {
        ctrl = VideoPlayerController.networkUrl(Uri.parse(path));
      } else {
        final filePath = path.startsWith('file:')
            ? Uri.parse(path).toFilePath()
            : path;
        final f = File(filePath);
        if (!await f.exists()) {
          setState(() => _error = '本地文件不存在');
          return;
        }
        ctrl = VideoPlayerController.file(f);
      }
      _controller = ctrl;
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      await ctrl.setLooping(false);
      if (!mounted) {
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
      if (!mounted) return;
      setState(() => _error = '播放器初始化失败：$e');
    }
  }

  @override
  void dispose() {
    final g = _guard;
    final c = _controller;
    _guard = null;
    _controller = null;
    g?.dispose();
    c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          _error!,
          style: TextStyle(color: tokens.danger, fontFamily: tokens.fontFamily),
        ),
      );
    }
    if (!_ready || _controller == null || _guard == null) {
      return const SizedBox(
        height: 200,
        child: Center(child: ProgressRing()),
      );
    }
    final ctrl = _controller!;
    final guard = _guard!;
    final size = ctrl.value.size;
    final vw = size.width <= 0 ? 16.0 : size.width;
    final vh = size.height <= 0 ? 9.0 : size.height;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ColoredBox(
              color: const Color(0xFF0F1115),
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: vw,
                  height: vh,
                  child: VideoPlayer(ctrl),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        AnimatedBuilder(
          animation: Listenable.merge([ctrl, guard]),
          builder: (context, _) {
            final playing = guard.uiPlaying;
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
                      ),
                      onPressed: () => guard.togglePlayPause(),
                    ),
                  ),
                ),
                Expanded(
                  child: _DialogScrubber(
                    controller: ctrl,
                    guard: guard,
                    playedColor: tokens.primary,
                    bufferedColor: tokens.primary.withValues(alpha: 0.25),
                    backgroundColor: tokens.surfaceMuted,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _DialogScrubber extends StatefulWidget {
  const _DialogScrubber({
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
  State<_DialogScrubber> createState() => _DialogScrubberState();
}

class _DialogScrubberState extends State<_DialogScrubber> {
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
