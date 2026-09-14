import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../../../shell/window_bootstrap.dart';
import 'video_player_dialog.dart' show resolveVideoItemPlayablePath;

/// 系统级全屏播放壳（VID-PLAYER P2.2）：`window_manager.setFullScreen` + Esc / 按钮退出。
Future<void> showVideoDesktopFullscreen(
  BuildContext context, {
  required VideoItem item,
  double initialVolume = 100,
}) async {
  var enteredFs = false;
  if (supportsCustomTitleBar) {
    try {
      final already = await windowManager.isFullScreen();
      if (!already) {
        await windowManager.setFullScreen(true);
        enteredFs = true;
      }
    } catch (_) {}
  }

  if (!context.mounted) {
    if (enteredFs && supportsCustomTitleBar) {
      try {
        await windowManager.setFullScreen(false);
      } catch (_) {}
    }
    return;
  }

  try {
    await Navigator.of(context, rootNavigator: true).push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        barrierDismissible: false,
        transitionDuration: FluentMotion.lightbox,
        reverseTransitionDuration: FluentMotion.lightbox,
        pageBuilder: (ctx, animation, secondaryAnimation) {
          return _DesktopFullscreenPage(
            item: item,
            initialVolume: initialVolume,
            onExit: () => Navigator.of(ctx).pop(),
          );
        },
        transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: FluentMotion.standard,
            ),
            child: child,
          );
        },
      ),
    );
  } finally {
    if (enteredFs && supportsCustomTitleBar) {
      try {
        await windowManager.setFullScreen(false);
      } catch (_) {}
    }
  }
}

class _DesktopFullscreenPage extends StatefulWidget {
  const _DesktopFullscreenPage({
    required this.item,
    required this.initialVolume,
    required this.onExit,
  });

  final VideoItem item;
  final double initialVolume;
  final VoidCallback onExit;

  @override
  State<_DesktopFullscreenPage> createState() => _DesktopFullscreenPageState();
}

class _DesktopFullscreenPageState extends State<_DesktopFullscreenPage> {
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

  @override
  void initState() {
    super.initState();
    // 入场时用调用方传入的音量作即时 UI；open 前再 load 共享 prefs 对齐跨壳。
    _volume = widget.initialVolume.clamp(0.0, 100.0);
    _volumeBeforeMute = _volume <= 0 ? 100 : _volume;
    _muted = _volume <= 0;
    _init();
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
              FilledButton(
                onPressed: _loading ? null : () => _retryPlayback(),
                child: const Text('重试'),
              ),
              const SizedBox(height: 12),
              Button(
                onPressed: widget.onExit,
                child: const Text('退出全屏'),
              ),
            ],
          ),
        ),
      );
    }

    final children = <Widget>[];
    if (_ready && _videoController != null) {
      children.add(
        Center(
          child: AspectRatio(
            aspectRatio: _stageAspectRatio(),
            child: Video(
              controller: _videoController!,
              controls: NoVideoControls,
              fit: BoxFit.contain,
            ),
          ),
        ),
      );
    } else {
      final poster = _buildPoster();
      if (poster != null) {
        children.add(
          Center(
            child: AspectRatio(
              aspectRatio: _stageAspectRatio(),
              child: poster,
            ),
          ),
        );
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

  Future<void> _setVolume(double value) async {
    final v = value.clamp(0.0, 100.0);
    setState(() {
      _volume = v;
      _muted = v <= 0;
      if (v > 0) _volumeBeforeMute = v;
    });
    _persistVolume();
    final player = _player;
    if (player != null) {
      try {
        await player.setVolume(v);
      } catch (_) {}
    }
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

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onExit();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ColoredBox(
        color: const Color(0xFF0F1115),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildStage(tokens),
            if (_ready && _player != null && _videoController != null) ...[
              Positioned(
                top: 12,
                right: 12,
                child: Tooltip(
                  message: '退出全屏 (Esc)',
                  child: Semantics(
                    button: true,
                    label: '退出全屏',
                    excludeSemantics: true,
                    child: IconButton(
                      icon: const Icon(
                        FluentIcons.back_to_window,
                        size: 18,
                        color: Colors.white,
                      ),
                      onPressed: widget.onExit,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: _buildTransport(tokens),
              ),
            ] else if (_error == null)
              Positioned(
                top: 12,
                right: 12,
                child: Tooltip(
                  message: '退出全屏 (Esc)',
                  child: Semantics(
                    button: true,
                    label: '退出全屏',
                    excludeSemantics: true,
                    child: IconButton(
                      icon: const Icon(
                        FluentIcons.back_to_window,
                        size: 18,
                        color: Colors.white,
                      ),
                      onPressed: widget.onExit,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransport(FluentTokens tokens) {
    final player = _player!;
    final playing = player.state.playing && !player.state.completed;
    final position = player.state.position;
    final duration = player.state.duration;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Tooltip(
              message: playing ? '暂停' : '播放',
              child: IconButton(
                icon: Icon(
                  playing ? FluentIcons.pause : FluentIcons.play,
                  size: 14,
                  color: Colors.white,
                ),
                onPressed: () => _toggle(),
              ),
            ),
            Expanded(
              child: _FsScrubber(player: player),
            ),
            const SizedBox(width: 8),
            Text(
              '${_fmt(position)} / ${_fmt(duration)}',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.8),
                fontFamily: tokens.fontFamily,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: _muted ? '取消静音' : '静音',
              child: IconButton(
                icon: Icon(
                  _muted
                      ? FluentIcons.volume_disabled
                      : FluentIcons.volume2,
                  size: 14,
                  color: Colors.white,
                ),
                onPressed: () => _toggleMute(),
              ),
            ),
            SizedBox(
              width: 110,
              child: Slider(
                value: _muted ? 0 : _volume,
                min: 0,
                max: 100,
                onChanged: (v) => _setVolume(v),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FsScrubber extends StatefulWidget {
  const _FsScrubber({required this.player});

  final Player player;

  @override
  State<_FsScrubber> createState() => _FsScrubberState();
}

class _FsScrubberState extends State<_FsScrubber> {
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
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(
          height: 4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: Colors.white.withValues(alpha: 0.2)),
                FractionallySizedBox(
                  widthFactor: buffered,
                  alignment: Alignment.centerLeft,
                  child: ColoredBox(
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
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
