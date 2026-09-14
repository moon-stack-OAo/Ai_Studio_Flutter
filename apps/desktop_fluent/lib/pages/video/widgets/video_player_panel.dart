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
  bool _loading = false;
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

  Future<void> _awaitDecodable(Player player, int token) async {
    bool ready() {
      final w = player.state.width;
      final h = player.state.height;
      return w != null && h != null && w > 0 && h > 0;
    }

    if (ready()) return;
    final done = Completer<void>();
    late final StreamSubscription<int?> sub;
    sub = player.stream.width.listen((_) {
      if (token != _bindToken || ready()) {
        if (!done.isCompleted) done.complete();
      }
    });
    try {
      await done.future.timeout(const Duration(milliseconds: 1200));
    } on TimeoutException {
      // 超时仍切换，避免卡住
    } finally {
      await sub.cancel();
    }
  }

  Future<void> _failBind({
    required int token,
    required Player? oldPlayer,
    required String message,
    required String? restoreBoundId,
    required String? restoreBoundPath,
    Player? failedPlayer,
  }) async {
    if (failedPlayer != null && !identical(failedPlayer, oldPlayer)) {
      await _disposePlayer(failedPlayer);
    }
    if (!mounted || token != _bindToken) {
      return;
    }
    final keepFrame = _ready && _videoController != null;
    if (keepFrame) {
      // 切换失败：保留上一任务画面；bound 回滚以便可重试
      _boundItemId = restoreBoundId;
      _boundPath = restoreBoundPath;
      if (_player != null && _subs.isEmpty) {
        _attachSubs(_player!);
      }
      setState(() {
        _loading = false;
        _error = message;
      });
      return;
    }
    _clearSubs();
    final current = _player;
    _player = null;
    _videoController = null;
    _boundItemId = null;
    _boundPath = null;
    setState(() {
      _ready = false;
      _loading = false;
      _error = message;
    });
    if (oldPlayer != null && !identical(oldPlayer, current)) {
      await _disposePlayer(oldPlayer);
    }
    await _disposePlayer(current);
  }

  Future<void> _bind(VideoItem item, {bool force = false}) async {
    if (!force && !_shouldRebind(item)) {
      return;
    }

    final path = resolveVideoItemPlayablePath(item);
    final token = ++_bindToken;
    final oldPlayer = _player;
    final keepFrame = _ready && _videoController != null;
    final prevBoundId = _boundItemId;
    final prevBoundPath = _boundPath;
    // 先记下目标，避免 loading 中 didUpdateWidget 重复 _bind
    _boundItemId = item.id;
    _boundPath = path;

    if (mounted) {
      setState(() {
        _error = null;
        _loading = true;
        if (!keepFrame) {
          _ready = false;
        }
      });
    }

    // 保留旧画面；先暂停旧源，避免切换时双路出声
    if (oldPlayer != null) {
      try {
        await oldPlayer.pause();
      } catch (_) {}
    }
    if (!mounted || token != _bindToken) return;

    if (path == null || path.isEmpty) {
      await _failBind(
        token: token,
        oldPlayer: oldPlayer,
        restoreBoundId: prevBoundId,
        restoreBoundPath: prevBoundPath,
        message: '没有可播放的视频地址',
      );
      return;
    }
    if (path.startsWith('memory://')) {
      await _failBind(
        token: token,
        oldPlayer: oldPlayer,
        restoreBoundId: prevBoundId,
        restoreBoundPath: prevBoundPath,
        message: '内存视频请先另存或系统打开',
      );
      return;
    }

    Player? created;
    try {
      if (!_isHttp(path)) {
        final filePath =
            path.startsWith('file:') ? Uri.parse(path).toFilePath() : path;
        final f = File(filePath);
        if (!await f.exists()) {
          await _failBind(
            token: token,
            oldPlayer: oldPlayer,
            restoreBoundId: prevBoundId,
            restoreBoundPath: prevBoundPath,
            message: '本地文件不存在',
          );
          return;
        }
      }

      created = Player();
      await created.setPlaylistMode(PlaylistMode.none);
      await created.setVolume(_muted ? 0 : _volume);
      if (!mounted || token != _bindToken) {
        await _disposePlayer(created);
        return;
      }
      final video = VideoController(created);

      // 先解码到可显示尺寸，再挂到舞台，避免黑帧闪一下
      await created.open(Media(_toMediaUri(path)), play: true);
      if (!mounted || token != _bindToken) {
        await _disposePlayer(created);
        return;
      }
      await _awaitDecodable(created, token);
      if (!mounted || token != _bindToken) {
        await _disposePlayer(created);
        return;
      }

      _clearSubs();
      final toDispose = _player;
      _player = created;
      _videoController = video;
      _attachSubs(created);
      setState(() {
        _ready = true;
        _loading = false;
        _error = null;
      });
      if (toDispose != null && !identical(toDispose, created)) {
        unawaited(_disposePlayer(toDispose));
      }
    } catch (e) {
      await _failBind(
        token: token,
        oldPlayer: oldPlayer,
        failedPlayer: created,
        restoreBoundId: prevBoundId,
        restoreBoundPath: prevBoundPath,
        message: '播放器初始化失败：$e',
      );
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
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: Color(0xFF0F1115),
                ),
                child: _buildStage(tokens),
              ),
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
            ],
          ),
        ],
      ),
    );
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

  Widget _buildStage(FluentTokens tokens) {
    if (_error != null && !_ready) {
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

    if (_loading) {
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
        SizedBox(
          width: 72,
          child: Slider(
            value: muted ? 0 : volume,
            min: 0,
            max: 100,
            label: '${(muted ? 0 : volume).round()}',
            onChanged: (v) => onVolumeChanged(v),
          ),
        ),
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
