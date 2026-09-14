import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// M-VideoPlayer：推页播放 + 音量 + 系统沉浸全屏（VID-PLAYER P2.1 / P2.2）。
class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({
    super.key,
    required this.item,
    this.onSaveAlbum,
    this.onShare,
    this.onOpenSystem,
    this.onRerun,
    this.rerunEnabled = true,
  });

  final VideoItem item;
  final void Function(VideoItem item)? onSaveAlbum;
  final void Function(VideoItem item)? onShare;
  final Future<bool> Function(VideoItem item)? onOpenSystem;
  /// `VID-RERUN`：用此提示重跑。
  final void Function(VideoItem item)? onRerun;
  final bool rerunEnabled;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  Player? _player;
  VideoController? _videoController;
  final List<StreamSubscription<dynamic>> _subs = [];
  String? _error;
  bool _ready = false;
  bool _loading = true;
  double _volume = 100;
  double _volumeBeforeMute = 100;
  bool _muted = false;
  bool _immersive = false;

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
        final path = _resolvePlayable(widget.item);
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
    final path = _resolvePlayable(widget.item);
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

  Widget _buildStage(MaterialTokens tokens) {
    if (_error != null && !_ready) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: tokens.danger,
                fontFamily: tokens.fontFamily,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loading ? null : () => _retryPlayback(),
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    final buffering =
        _ready && _player != null && _player!.state.buffering && !_loading;
    final showSpinner = _loading || buffering;

    Widget stageCore() {
      if (_ready && _videoController != null) {
        return Video(
          controller: _videoController!,
          controls: NoVideoControls,
          fit: BoxFit.contain,
        );
      }
      final poster = _buildPoster();
      if (poster != null) {
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: poster),
            if (showSpinner)
              const ColoredBox(
                color: Color(0x66000000),
                child: Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
          ],
        );
      }
      if (showSpinner) {
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      }
      return const SizedBox.shrink();
    }

    if (_immersive) {
      return SizedBox.expand(
        child: _ready && _videoController != null && showSpinner
            ? Stack(
                fit: StackFit.expand,
                children: [
                  stageCore(),
                  const ColoredBox(
                    color: Color(0x66000000),
                    child: Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
                ],
              )
            : stageCore(),
      );
    }

    return AspectRatio(
      aspectRatio: _stageAspectRatio(),
      child: DecoratedBox(
        decoration: const BoxDecoration(color: Color(0xFF0F1115)),
        child: _ready && _videoController != null && showSpinner
            ? Stack(
                fit: StackFit.expand,
                children: [
                  stageCore(),
                  const ColoredBox(
                    color: Color(0x66000000),
                    child: Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
                ],
              )
            : stageCore(),
      ),
    );
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

  Future<void> _restoreSystemUi() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } catch (_) {}
  }

  Future<void> _enterImmersive() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } catch (_) {}
    if (mounted) setState(() => _immersive = true);
  }

  Future<void> _exitImmersive() async {
    await _restoreSystemUi();
    if (mounted) setState(() => _immersive = false);
  }

  Future<void> _handleBack() async {
    if (_immersive) {
      await _exitImmersive();
      return;
    }
    if (mounted) await Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    unawaited(VideoPlaybackPrefsWriter.instance.flush());
    unawaited(_restoreSystemUi());
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

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    return PopScope(
      canPop: !_immersive,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: _immersive
            ? null
            : AppBar(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                title: const Text('播放'),
                leading: IconButton(
                  tooltip: '返回',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => _handleBack(),
                ),
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
                  if (widget.onRerun != null &&
                      (widget.item.prompt.trim().isNotEmpty ||
                          widget.item.referenceImages.isNotEmpty))
                    IconButton(
                      tooltip: '用此提示重跑',
                      icon: const Icon(Icons.replay),
                      onPressed: widget.rerunEnabled
                          ? () {
                              widget.onRerun!(widget.item);
                              Navigator.of(context).maybePop();
                            }
                          : null,
                    ),
                  if (_ready)
                    IconButton(
                      tooltip: '全屏',
                      icon: const Icon(Icons.fullscreen),
                      onPressed: () => _enterImmersive(),
                    ),
                ],
              ),
        body: ColoredBox(
          color: const Color(0xFF0F1115),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(child: _buildStage(tokens)),
              if (_ready && _player != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SafeArea(
                    child: _ControlsBar(
                      player: _player!,
                      muted: _muted,
                      volume: _volume,
                      immersive: _immersive,
                      fmt: _fmt,
                      onToggle: _toggle,
                      onToggleMute: _toggleMute,
                      onVolumeChanged: _setVolume,
                      onEnterFullscreen: _enterImmersive,
                      onExitFullscreen: _exitImmersive,
                    ),
                  ),
                ),
              if (_immersive)
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 8,
                  right: 8,
                  child: IconButton(
                    color: Colors.white,
                    tooltip: '退出全屏',
                    icon: const Icon(Icons.fullscreen_exit),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      tapTargetSize: MaterialTapTargetSize.padded,
                    ),
                    onPressed: () => _exitImmersive(),
                  ),
                ),
            ],
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

class _ControlsBar extends StatelessWidget {
  const _ControlsBar({
    required this.player,
    required this.muted,
    required this.volume,
    required this.immersive,
    required this.fmt,
    required this.onToggle,
    required this.onToggleMute,
    required this.onVolumeChanged,
    required this.onEnterFullscreen,
    required this.onExitFullscreen,
  });

  final Player player;
  final bool muted;
  final double volume;
  final bool immersive;
  final String Function(Duration) fmt;
  final Future<void> Function() onToggle;
  final Future<void> Function() onToggleMute;
  final Future<void> Function(double value) onVolumeChanged;
  final Future<void> Function() onEnterFullscreen;
  final Future<void> Function() onExitFullscreen;

  @override
  Widget build(BuildContext context) {
    final playing = player.state.playing && !player.state.completed;
    final position = player.state.position;
    final duration = player.state.duration;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  color: Colors.white,
                  tooltip: playing ? '暂停' : '播放',
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                  onPressed: () => onToggle(),
                ),
                Expanded(
                  child: _MobileScrubber(player: player),
                ),
                const SizedBox(width: 8),
                Text(
                  '${fmt(position)} / ${fmt(duration)}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                IconButton(
                  color: Colors.white,
                  tooltip: immersive ? '退出全屏' : '全屏',
                  icon: Icon(
                    immersive ? Icons.fullscreen_exit : Icons.fullscreen,
                  ),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                  onPressed: () =>
                      immersive ? onExitFullscreen() : onEnterFullscreen(),
                ),
              ],
            ),
            Row(
              children: [
                IconButton(
                  color: Colors.white,
                  tooltip: muted ? '取消静音' : '静音',
                  icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                  onPressed: () => onToggleMute(),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 7,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 14,
                      ),
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: muted ? 0 : volume,
                      min: 0,
                      max: 100,
                      onChanged: (v) => onVolumeChanged(v),
                    ),
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: Text(
                    '${(muted ? 0 : volume).round()}',
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
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

class _MobileScrubber extends StatefulWidget {
  const _MobileScrubber({required this.player});

  final Player player;

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
    final target =
        Duration(milliseconds: (d.inMilliseconds * clamped).round());
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
  }
}
