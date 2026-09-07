import 'dart:io';

import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// M-VideoPlayer：全屏播放页，pop 即 dispose。
class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({
    super.key,
    required this.item,
    this.onSaveAlbum,
    this.onOpenSystem,
  });

  final VideoItem item;
  final void Function(VideoItem item)? onSaveAlbum;
  final Future<bool> Function(VideoItem item)? onOpenSystem;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  VideoPlayerController? _controller;
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
      setState(() => _ready = true);
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
    final c = _controller;
    _controller = null;
    c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('播放'),
        actions: [
          if (widget.onSaveAlbum != null)
            IconButton(
              tooltip: '存相册',
              icon: const Icon(Icons.save_alt),
              onPressed: () => widget.onSaveAlbum!(widget.item),
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
            : !_ready || _controller == null
                ? const CircularProgressIndicator(color: Colors.white)
                : _PlayerStage(
                    controller: _controller!,
                    fallbackAspectRatio: _parseAspect(widget.item.aspectRatio),
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
    this.fallbackAspectRatio,
  });

  final VideoPlayerController controller;
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
          child: ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              return Row(
                children: [
                  IconButton(
                    color: Colors.white,
                    tooltip: value.isPlaying ? '暂停' : '播放',
                    icon: Icon(
                      value.isPlaying ? Icons.pause : Icons.play_arrow,
                    ),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      tapTargetSize: MaterialTapTargetSize.padded,
                    ),
                    onPressed: () {
                      if (value.isPlaying) {
                        controller.pause();
                      } else {
                        controller.play();
                      }
                    },
                  ),
                  Expanded(
                    child: VideoProgressIndicator(
                      controller,
                      allowScrubbing: true,
                      colors: const VideoProgressColors(
                        playedColor: Colors.white,
                        bufferedColor: Colors.white38,
                        backgroundColor: Colors.white24,
                      ),
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
