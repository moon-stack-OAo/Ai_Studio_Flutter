import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'video_desktop_fullscreen.dart';
import 'video_player_dialog.dart' show resolveVideoItemPlayablePath;

/// F-VideoPlayer · VID-PLAYER：主区内嵌播放面板。
class VideoPlayerPanel extends StatefulWidget {
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
  State<VideoPlayerPanel> createState() => _VideoPlayerPanelState();
}

class _VideoPlayerPanelState extends State<VideoPlayerPanel> {
  final GlobalKey<_InlinePlayerState> _inlineKey =
      GlobalKey<_InlinePlayerState>();

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    final item = widget.item;
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
                if (item != null && widget.onExpand != null) ...[
                  const SizedBox(width: 8),
                  HyperlinkButton(
                    onPressed: () {
                      // 方案 A：弹窗独立 Player，打开时内嵌暂停。
                      _inlineKey.currentState?.pausePlayback();
                      widget.onExpand!();
                    },
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
                    key: _inlineKey,
                    item: item,
                    tokens: tokens,
                    onOpenSystem: widget.onOpenSystem,
                    onSaveAs: widget.onSaveAs,
                  ),
          ),
        ],
      ),
    );
  }
}

String _stageLabel(VideoItem? item) {
  final raw = item?.aspectRatio?.trim();
  if (raw != null && raw.isNotEmpty) return '$raw · 音量 / 真全屏';
  return '音量 / 真全屏';
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
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '选择左侧已完成任务',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.88),
                          fontFamily: tokens.fontFamily,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '成功项封面或「在右侧播放」会载入此舞台。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.5,
                          color: Colors.white.withValues(alpha: 0.55),
                          fontFamily: tokens.fontFamily,
                        ),
                      ),
                    ],
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
  Player? _player;
  VideoController? _videoController;
  final List<StreamSubscription<dynamic>> _subs = [];
  String? _error;
  bool _ready = false;
  String? _boundItemId;
  String? _boundPath;
  int _bindToken = 0;
  double _volume = 100;
  double _volumeBeforeMute = 100;
  bool _muted = false;

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
    if (_ready && _player != null) {
      final upgradingToLocal = _isHttp(_boundPath) && !_isHttp(next);
      if (upgradingToLocal) return false;
    }
    return true;
  }

  bool _isHttp(String? path) {
    final s = (path ?? '').trim();
    return RegExp(r'^https?://', caseSensitive: false).hasMatch(s);
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
    _clearSubs();
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
        setState(() => _error = '播放出错：$msg');
      }),
    ]);
  }

  Future<void> _setVolume(double value) async {
    final v = value.clamp(0.0, 100.0);
    setState(() {
      _volume = v;
      _muted = v <= 0;
      if (v > 0) _volumeBeforeMute = v;
    });
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
    await pausePlayback();
    if (!mounted) return;
    await showVideoDesktopFullscreen(
      context,
      item: widget.item,
      initialVolume: _muted ? 0 : _volume,
    );
  }

  Future<void> _disposePlayer(Player? player) async {
    if (player == null) return;
    try {
      await player.dispose();
    } catch (_) {}
  }

  Future<void> pausePlayback() async {
    final p = _player;
    if (p == null) return;
    try {
      await p.pause();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _bind(VideoItem item, {bool force = false}) async {
    if (!force && !_shouldRebind(item)) {
      return;
    }

    final path = resolveVideoItemPlayablePath(item);
    final token = ++_bindToken;
    final old = _player;
    _clearSubs();
    _player = null;
    _videoController = null;
    _boundItemId = item.id;
    _boundPath = path;
    if (mounted) {
      setState(() {
        _ready = false;
        _error = null;
      });
    }
    await _disposePlayer(old);
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
      if (!_isHttp(path)) {
        final filePath =
            path.startsWith('file:') ? Uri.parse(path).toFilePath() : path;
        final f = File(filePath);
        if (!await f.exists()) {
          if (mounted && token == _bindToken) {
            setState(() => _error = '本地文件不存在');
          }
          return;
        }
      }

      final player = Player();
      await player.setPlaylistMode(PlaylistMode.none);
      await player.setVolume(_muted ? 0 : _volume);
      if (!mounted || token != _bindToken) {
        await _disposePlayer(player);
        return;
      }
      final video = VideoController(player);
      _player = player;
      _videoController = video;
      _attachSubs(player);

      await player.open(Media(_toMediaUri(path)), play: true);
      if (!mounted || token != _bindToken) {
        _clearSubs();
        _player = null;
        _videoController = null;
        await _disposePlayer(player);
        return;
      }
      setState(() => _ready = true);
    } catch (e) {
      if (!mounted || token != _bindToken) return;
      setState(() => _error = '播放器初始化失败：$e');
    }
  }

  @override
  void dispose() {
    _bindToken++;
    _clearSubs();
    final p = _player;
    _player = null;
    _videoController = null;
    unawaited(_disposePlayer(p));
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
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
          if (_ready && _player != null) ...[
            const SizedBox(height: 10),
            _Transport(
              player: _player!,
              tokens: tokens,
              fmt: _fmt,
              muted: _muted,
              volume: _volume,
              onToggleMute: _toggleMute,
              onVolumeChanged: _setVolume,
              onFullscreen: _enterFullscreen,
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
              if (_ready)
                Button(
                  onPressed: () => _enterFullscreen(),
                  child: const Text('全屏'),
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
    if (!_ready || _videoController == null) {
      return const Center(child: ProgressRing());
    }
    return Video(
      controller: _videoController!,
      controls: NoVideoControls,
      fit: BoxFit.contain,
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({
    required this.player,
    required this.tokens,
    required this.fmt,
    required this.muted,
    required this.volume,
    required this.onToggleMute,
    required this.onVolumeChanged,
    required this.onFullscreen,
  });

  final Player player;
  final FluentTokens tokens;
  final String Function(Duration) fmt;
  final bool muted;
  final double volume;
  final Future<void> Function() onToggleMute;
  final Future<void> Function(double value) onVolumeChanged;
  final Future<void> Function() onFullscreen;

  Future<void> _toggle() async {
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
    final state = player.state;
    final playing = state.playing && !state.completed;
    final position = state.position;
    final duration = state.duration;
    return Column(
      children: [
        Row(
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
                  onPressed: () => _toggle(),
                ),
              ),
            ),
            Expanded(
              child: _Scrubber(
                player: player,
                playedColor: tokens.primary,
                bufferedColor: tokens.primary.withValues(alpha: 0.25),
                backgroundColor: tokens.surfaceMuted,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${fmt(position)} / ${fmt(duration)}',
              style: TextStyle(
                fontSize: 11,
                color: tokens.inkMuted,
                fontFamily: tokens.fontFamily,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: '全屏',
              child: Semantics(
                button: true,
                label: '全屏',
                excludeSemantics: true,
                child: IconButton(
                  icon: const Icon(FluentIcons.full_screen, size: 14),
                  onPressed: () => onFullscreen(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Tooltip(
              message: muted ? '取消静音' : '静音',
              child: Semantics(
                button: true,
                label: muted ? '取消静音' : '静音',
                excludeSemantics: true,
                child: IconButton(
                  icon: Icon(
                    muted ? FluentIcons.volume_disabled : FluentIcons.volume2,
                    size: 14,
                  ),
                  onPressed: () => onToggleMute(),
                ),
              ),
            ),
            Expanded(
              child: Slider(
                value: muted ? 0 : volume,
                min: 0,
                max: 100,
                label: '${(muted ? 0 : volume).round()}',
                onChanged: (v) => onVolumeChanged(v),
              ),
            ),
            SizedBox(
              width: 36,
              child: Text(
                '${(muted ? 0 : volume).round()}',
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 11,
                  color: tokens.inkMuted,
                  fontFamily: tokens.fontFamily,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Scrubber extends StatefulWidget {
  const _Scrubber({
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
  State<_Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends State<_Scrubber> {
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
    );
  }
}
