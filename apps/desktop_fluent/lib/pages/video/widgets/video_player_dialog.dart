import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'video_desktop_fullscreen.dart';
import 'video_tool_chrome.dart';

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
          VideoToolButton(
            onPressed: () async {
              await onSaveAs(item);
            },
            child: const Text('另存为'),
          ),
          VideoToolButton(
            onPressed: () async {
              await onOpenSystem(item);
            },
            child: const Text('系统打开'),
          ),
          VideoToolButton(
            filled: true,
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
  Player? _player;
  VideoController? _videoController;
  final List<StreamSubscription<dynamic>> _subs = [];
  String? _error;
  bool _ready = false;
  bool _loading = true;
  double _volume = 100;
  double _volumeBeforeMute = 100;
  bool _muted = false;

  bool _isHttp(String path) {
    return RegExp(r'^https?://', caseSensitive: false).hasMatch(path);
  }

  String _toMediaUri(String path) {
    if (_isHttp(path)) return path;
    if (path.startsWith('file:')) return path;
    return Uri.file(path).toString();
  }

  void _clearSubs() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
  }

  void _attachSubs(Player player) {
    void tick([Object? _]) {
      if (mounted) setState(() {});
    }

    _subs.addAll([
      player.stream.playing.listen(tick),
      player.stream.completed.listen(tick),
      player.stream.position.listen(tick),
      player.stream.duration.listen(tick),
      player.stream.buffer.listen(tick),
      player.stream.buffering.listen(tick),
      player.stream.width.listen(tick),
      player.stream.height.listen(tick),
      player.stream.volume.listen((v) {
        if (!mounted || _muted) return;
        setState(() => _volume = v.clamp(0.0, 100.0));
      }),
      player.stream.error.listen((msg) {
        if (!mounted || msg.trim().isEmpty) return;
        final path = resolveVideoItemPlayablePath(widget.item);
        setState(() {
          _ready = false;
          _error = VideoPlaybackErrors.streamFailed(
            msg,
            isRemote: path != null && _isHttp(path),
          );
        });
      }),
    ]);
  }

  Future<void> _loadVolumePrefs() async {
    final prefs = await VideoPlaybackPrefsWriter.instance.load();
    if (!mounted) return;
    setState(() {
      _volume = prefs.volume;
      _volumeBeforeMute =
          prefs.volume <= 0 ? VideoPlaybackPrefs.defaultVolume : prefs.volume;
      _muted = prefs.muted;
    });
  }

  void _persistVolume() {
    VideoPlaybackPrefsWriter.instance.scheduleSave(
      VideoPlaybackPrefs.fromUi(
        volume: _volume,
        volumeBeforeMute: _volumeBeforeMute,
        muted: _muted,
      ),
    );
  }

  Future<void> _setVolume(double value) async {
    final v = value.clamp(0.0, 100.0);
    setState(() {
      _volume = v;
      _muted = v <= 0;
      if (v > 0) _volumeBeforeMute = v;
    });
    _persistVolume();
    final player = _player;
    if (player == null) return;
    try {
      await player.setVolume(v);
    } catch (_) {}
  }

  Future<void> _toggleMute() async {
    if (_muted) {
      final restore = _volumeBeforeMute <= 0 ? 100.0 : _volumeBeforeMute;
      await _setVolume(restore);
      return;
    }
    _volumeBeforeMute = _volume <= 0 ? 100.0 : _volume;
    await _setVolume(0);
  }

  Future<void> _enterFullscreen() async {
    final player = _player;
    if (player != null) {
      try {
        await player.pause();
      } catch (_) {}
    }
    if (!mounted) return;
    await showVideoDesktopFullscreen(
      context,
      item: widget.item,
      initialVolume: _muted ? 0 : _volume,
    );
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _retryPlayback() async {
    await _disposeCurrentPlayer();
    if (!mounted) return;
    setState(() {
      _error = null;
      _ready = false;
      _loading = true;
    });
    await _init();
  }

  Future<void> _disposeCurrentPlayer() async {
    _clearSubs();
    final p = _player;
    _player = null;
    _videoController = null;
    if (p == null) return;
    try {
      await p.dispose();
    } catch (_) {}
  }

  Future<void> _init() async {
    if (mounted) {
      setState(() {
        _error = null;
        _loading = true;
        _ready = false;
      });
    }
    final path = resolveVideoItemPlayablePath(widget.item);
    if (path == null || path.isEmpty) {
      setState(() {
        _loading = false;
        _error = VideoPlaybackErrors.noAddress;
      });
      return;
    }
    if (path.startsWith('memory://')) {
      setState(() {
        _loading = false;
        _error = VideoPlaybackErrors.memoryOnly;
      });
      return;
    }
    final remote = _isHttp(path);
    try {
      if (!remote) {
        final filePath =
            path.startsWith('file:') ? Uri.parse(path).toFilePath() : path;
        final f = File(filePath);
        if (!await f.exists()) {
          setState(() {
            _loading = false;
            _error = VideoPlaybackErrors.localMissing;
          });
          return;
        }
      }

      await _loadVolumePrefs();
      if (!mounted) return;

      final player = Player();
      await player.setPlaylistMode(PlaylistMode.none);
      await player.setVolume(_muted ? 0 : _volume);
      if (!mounted) {
        await player.dispose();
        return;
      }
      final video = VideoController(player);
      _player = player;
      _videoController = video;
      _attachSubs(player);

      await player.open(Media(_toMediaUri(path)), play: true);
      if (!mounted) {
        _clearSubs();
        _player = null;
        _videoController = null;
        await player.dispose();
        return;
      }
      setState(() {
        _ready = true;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      await _disposeCurrentPlayer();
      if (!mounted) return;
      setState(() {
        _ready = false;
        _loading = false;
        _error = VideoPlaybackErrors.initFailed(e, isRemote: remote);
      });
    }
  }

  Widget? _buildPoster() {
    final local = (widget.item.posterLocalPath ?? '').trim();
    if (local.isNotEmpty && !local.startsWith('memory-poster://')) {
      final file = File(local);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        );
      }
    }
    final url = (widget.item.posterUrl ?? '').trim();
    if (VideoPosterService.isRemotePosterUrl(url)) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    }
    return null;
  }

  double _stageAspectRatio() {
    final p = _player;
    if (_ready && p != null) {
      final w = p.state.width;
      final h = p.state.height;
      if (w != null && h != null && w > 0 && h > 0) {
        return w / h;
      }
    }
    return _parseAspect(widget.item.aspectRatio) ?? (16 / 9);
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

  Widget _buildStage(FluentTokens tokens) {
    if (_error != null && !_ready) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: tokens.danger,
                  fontFamily: tokens.fontFamily,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _loading ? null : () => _retryPlayback(),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    final children = <Widget>[];
    if (_ready && _videoController != null) {
      children.add(
        Video(
          controller: _videoController!,
          controls: NoVideoControls,
          fit: BoxFit.contain,
        ),
      );
    } else {
      final poster = _buildPoster();
      if (poster != null) {
        children.add(Positioned.fill(child: poster));
      }
    }

    final buffering =
        _ready && _player != null && _player!.state.buffering && !_loading;
    if (_loading || buffering) {
      children.add(
        const ColoredBox(
          color: Color(0x66000000),
          child: Center(child: ProgressRing()),
        ),
      );
    }

    if (children.isEmpty) {
      return const Center(child: ProgressRing());
    }
    if (children.length == 1) {
      return children.first;
    }
    return Stack(fit: StackFit.expand, children: children);
  }

  @override
  void dispose() {
    unawaited(VideoPlaybackPrefsWriter.instance.flush());
    unawaited(_disposeCurrentPlayer());
    super.dispose();
  }

  Future<void> _toggle() async {
    final player = _player;
    if (player == null) return;
    final state = player.state;
    if (state.playing) {
      await player.pause();
      return;
    }
    if (state.completed ||
        (state.duration > Duration.zero &&
            state.position >=
                state.duration - const Duration(milliseconds: 80))) {
      await player.seek(Duration.zero);
    }
    await player.play();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    final player = _player;
    final readyPlayer =
        (_ready && player != null && _videoController != null) ? player : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF0F1115),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Center(
                child: AspectRatio(
                  aspectRatio: _stageAspectRatio(),
                  child: _buildStage(tokens),
                ),
              ),
            ),
          ),
        ),
        if (readyPlayer != null) ...[
          const SizedBox(height: 12),
          _buildTransport(tokens, readyPlayer),
        ],
      ],
    );
  }

  Widget _buildTransport(FluentTokens tokens, Player player) {
    final playing = player.state.playing && !player.state.completed;
    final position = player.state.position;
    final duration = player.state.duration;
    final volShown = (_muted ? 0 : _volume).round();
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          VideoTransportIconButton(
            icon: playing ? FluentIcons.pause : FluentIcons.play,
            tooltip: playing ? '暂停' : '播放',
            onPressed: () => _toggle(),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _DialogScrubber(
              player: player,
              playedColor: tokens.primary,
              bufferedColor: tokens.inkMuted.withValues(alpha: 0.28),
              backgroundColor: tokens.canvas,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${_fmt(position)} / ${_fmt(duration)}',
            style: TextStyle(
              fontSize: 12,
              color: tokens.inkSecondary,
              fontFamily: tokens.fontFamily,
              fontFeatures: const [FontFeature.tabularFigures()],
              letterSpacing: 0.02,
            ),
          ),
          const SizedBox(width: 8),
          VideoTransportIconButton(
            icon: _muted ? FluentIcons.volume_disabled : FluentIcons.volume2,
            tooltip: _muted ? '取消静音' : '音量 · 跨启动持久化',
            semanticLabel: _muted ? '取消静音' : '静音',
            onPressed: () => _toggleMute(),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 72,
            child: Slider(
              value: _muted ? 0 : _volume,
              min: 0,
              max: 100,
              label: '$volShown%',
              onChanged: (v) => _setVolume(v),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 34,
            child: Text(
              '$volShown%',
              style: TextStyle(
                fontSize: 11,
                color: tokens.inkSecondary,
                fontFamily: tokens.fontFamily,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 4),
          VideoTransportIconButton(
            icon: FluentIcons.full_screen,
            tooltip: '全屏',
            onPressed: () => _enterFullscreen(),
          ),
        ],
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _DialogScrubber extends StatefulWidget {
  const _DialogScrubber({
    required this.player,
    required this.playedColor,
    required this.bufferedColor,
    required this.backgroundColor,
  });

  final Player player;
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

  double _progressFraction() {
    final d = widget.player.state.duration.inMilliseconds;
    if (d <= 0) return 0;
    if (widget.player.state.completed) return 1;
    return (widget.player.state.position.inMilliseconds / d).clamp(0.0, 1.0);
  }

  double _bufferedFraction() {
    final d = widget.player.state.duration.inMilliseconds;
    if (d <= 0) return 0;
    return (widget.player.state.buffer.inMilliseconds / d).clamp(0.0, 1.0);
  }

  Future<void> _seekFraction(double fraction, {required bool resume}) async {
    final d = widget.player.state.duration;
    if (d <= Duration.zero) return;
    final clamped = fraction.clamp(0.0, 1.0);
    final target = Duration(milliseconds: (d.inMilliseconds * clamped).round());
    await widget.player.seek(target);
    final atEnd = target >= d - const Duration(milliseconds: 80);
    if (!resume || atEnd) {
      await widget.player.pause();
    } else {
      await widget.player.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final fraction = _dragFraction ?? _progressFraction();
    final buffered = _bufferedFraction();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) {
        _wasPlaying = widget.player.state.playing;
        setState(() => _dragFraction = fraction);
      },
      onHorizontalDragUpdate: (details) {
        setState(() => _dragFraction = _fractionOf(details.globalPosition));
      },
      onHorizontalDragEnd: (_) async {
        final f = _dragFraction ?? fraction;
        setState(() => _dragFraction = null);
        await _seekFraction(f, resume: _wasPlaying);
      },
      onTapDown: (details) async {
        final f = _fractionOf(details.globalPosition);
        await _seekFraction(f, resume: widget.player.state.playing);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: SizedBox(
          height: 12,
          child: Stack(
            alignment: Alignment.centerLeft,
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                top: 4,
                bottom: 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: widget.backgroundColor,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: widget.playedColor.withValues(alpha: 0.12),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        FractionallySizedBox(
                          widthFactor: buffered,
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
              Align(
                alignment: Alignment(-1 + 2 * fraction.clamp(0.0, 1.0), 0),
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: widget.playedColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.28),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
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
