import 'dart:io';

import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../shell/back_host.dart';
import 'video_playback_guard.dart';

/// M-VideoPlayer：全屏播放页，pop 即 dispose。
class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({
    super.key,
    required this.item,
    this.onSaveAlbum,
    this.onShare,
    this.onOpenSystem,
  });

  final VideoItem item;
  final void Function(VideoItem item)? onSaveAlbum;
  final void Function(VideoItem item)? onShare;
  final Future<bool> Function(VideoItem item)? onOpenSystem;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
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
    final path = _resolvePlayable(widget.item);
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
      final VideoPlaybackGuard guard;
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
      guard = VideoPlaybackGuard(ctrl);
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

  String? _resolvePlayable(VideoItem item) {
    final local = item.localPath?.trim();
    if (local != null && isPlayableVideoPath(local)) return local;
    final url = item.videoUrl?.trim();
    if (url != null && isPlayableVideoPath(url)) return url;
    final remote = item.remoteVideoUrl?.trim();
    if (remote != null && isPlayableVideoPath(remote)) return remote;
    return null;
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
    final tokens = materialTokensOf(context);
    return BackHost(
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('播放'),
          leading: BackHost.leadingButton(context),
          actions: [
            if (widget.onSaveAlbum != null)
              IconButton(
                tooltip: '存相册',
                icon: const Icon(Icons.save_alt),
                onPressed: () => widget.onSaveAlbum!(widget.item),
              ),
            if (widget.onShare != null)
              IconButton(
                tooltip: '分享',
                icon: const Icon(Icons.share_outlined),
                onPressed: () => widget.onShare!(widget.item),
              ),
            if (widget.onOpenSystem != null)
              IconButton(
                tooltip: '系统打开',
                icon: const Icon(Icons.open_in_new),
                onPressed: () => widget.onOpenSystem!(widget.item),
              ),
          ],
        ),
        body: Center(
          child: _error != null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: tokens.danger,
                      fontFamily: tokens.fontFamily,
                    ),
                  ),
                )
              : !_ready || _controller == null || _guard == null
                  ? const CircularProgressIndicator(color: Colors.white)
                  : _PlayerStage(
                      controller: _controller!,
                      guard: _guard!,
                      fallbackAspectRatio:
                          _parseAspect(widget.item.aspectRatio),
                    ),
        ),
      ),
    );
  }

  static double? _parseAspect(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return null;
    final parts = s.split(':');
    if (parts.length != 2) return null;
    final w = double.tryParse(parts[0].trim());
    final h = double.tryParse(parts[1].trim());
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return w / h;
  }
}

class _PlayerStage extends StatelessWidget {
  const _PlayerStage({
    required this.controller,
    required this.guard,
    this.fallbackAspectRatio,
  });

  final VideoPlayerController controller;
  final VideoPlaybackGuard guard;
  final double? fallbackAspectRatio;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: controller,
          builder: (context, value, child) {
            final ar = value.aspectRatio > 0
                ? value.aspectRatio
                : (fallbackAspectRatio ?? 16 / 9);
            return AspectRatio(
              aspectRatio: ar,
              child: child,
            );
          },
          child: VideoPlayer(controller),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AnimatedBuilder(
            animation: Listenable.merge([controller, guard]),
            builder: (context, _) {
              final playing = guard.uiPlaying;
              return Row(
                children: [
                  IconButton(
                    color: Colors.white,
                    tooltip: playing ? '暂停' : '播放',
                    icon: Icon(
                      playing ? Icons.pause : Icons.play_arrow,
                    ),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      tapTargetSize: MaterialTapTargetSize.padded,
                    ),
                    onPressed: () => guard.togglePlayPause(),
                  ),
                  Expanded(
                    child: _MobileScrubber(
                      controller: controller,
                      guard: guard,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MobileScrubber extends StatefulWidget {
  const _MobileScrubber({
    required this.controller,
    required this.guard,
  });

  final VideoPlayerController controller;
  final VideoPlaybackGuard guard;

  @override
  State<_MobileScrubber> createState() => _MobileScrubberState();
}

class _MobileScrubberState extends State<_MobileScrubber> {
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
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: SizedBox(
              height: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: Colors.white24),
                    FractionallySizedBox(
                      widthFactor: buffered.clamp(0.0, 1.0),
                      alignment: Alignment.centerLeft,
                      child: const ColoredBox(color: Colors.white38),
                    ),
                    FractionallySizedBox(
                      widthFactor: fraction.clamp(0.0, 1.0),
                      alignment: Alignment.centerLeft,
                      child: const ColoredBox(color: Colors.white),
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
