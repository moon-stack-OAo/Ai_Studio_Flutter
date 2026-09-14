import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'video_desktop_fullscreen.dart';
import 'video_player_dialog.dart' show resolveVideoItemPlayablePath;
import 'video_tool_chrome.dart';

/// F-VideoPlayer · VID-PLAYER：主区内嵌播放面板。
class VideoPlayerPanel extends StatefulWidget {
  const VideoPlayerPanel({
    super.key,
    required this.item,
    required this.onOpenSystem,
    required this.onSaveAs,
    this.onExpand,
    this.onRerun,
    this.rerunEnabled = true,
  });

  final VideoItem? item;
  final Future<bool> Function(VideoItem item) onOpenSystem;
  final Future<bool> Function(VideoItem item) onSaveAs;
  final VoidCallback? onExpand;
  /// `VID-RERUN`：用此提示重跑。
  final void Function(VideoItem item)? onRerun;
  final bool rerunEnabled;

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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: tokens.border)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '播放器',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: tokens.ink,
                      fontFamily: tokens.fontFamily,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  flex: 2,
                  child: _PlayerHeaderMeta(
                    item: item,
                    tokens: tokens,
                  ),
                ),
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
                    onRerun: widget.onRerun,
                    rerunEnabled: widget.rerunEnabled,
                    onExpand: widget.onExpand == null
                        ? null
                        : () {
                            _inlineKey.currentState?.pausePlayback();
                            widget.onExpand!();
                          },
                  ),
          ),
        ],
      ),
    );
  }
}

String _snipPrompt(String raw, {int maxChars = 36}) {
  final t = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.isEmpty) return '';
  final runes = t.runes.toList();
  if (runes.length <= maxChars) return t;
  return '${String.fromCharCodes(runes.take(maxChars))}…';
}

List<String> _metaChipsFor(VideoItem item) {
  final chips = <String>[];
  final d = item.duration;
  if (d != null && d > 0) chips.add('${d}s');
  final ar = item.aspectRatio?.trim();
  if (ar != null && ar.isNotEmpty) chips.add(ar);
  final model = item.model.trim();
  if (model.isNotEmpty) chips.add(model);
  return chips;
}

class _PlayerHeaderMeta extends StatelessWidget {
  const _PlayerHeaderMeta({
    required this.item,
    required this.tokens,
  });

  final VideoItem? item;
  final FluentTokens tokens;

  @override
  Widget build(BuildContext context) {
    if (item == null) {
      return Align(
        alignment: Alignment.centerRight,
        child: Text(
          '音量跨启动持久化 · 真全屏',
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 11,
            height: 1.45,
            color: tokens.inkMuted,
            fontFamily: tokens.fontFamily,
          ),
        ),
      );
    }

    final snip = _snipPrompt(item!.prompt);
    final chips = _metaChipsFor(item!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (snip.isNotEmpty)
          Tooltip(
            message: item!.prompt.trim(),
            child: Text(
              snip,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: tokens.inkSecondary,
                fontFamily: tokens.fontFamily,
              ),
            ),
          ),
        if (chips.isNotEmpty) ...[
          if (snip.isNotEmpty) const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            alignment: WrapAlignment.end,
            children: [
              for (final c in chips)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: tokens.surfaceMuted,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: tokens.border),
                  ),
                  child: Text(
                    c,
                    style: TextStyle(
                      fontSize: 10,
                      color: tokens.inkMuted,
                      fontFamily: tokens.fontFamily,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
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
                      const _StageSilhouette(),
                      const SizedBox(height: 10),
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
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        alignment: WrapAlignment.center,
                        children: const [
                          _StepChip(label: '① 选完成项'),
                          _StepChip(label: '② 点封面或「在右侧播放」'),
                          _StepChip(label: '③ 载入此舞台'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'VID-RESUME 可恢复未完成任务。音量写入 prefs；重跑仅回填提示词与参考图，不自动提交。',
            style: TextStyle(
              fontSize: 11,
              height: 1.45,
              color: tokens.inkMuted,
              fontFamily: tokens.fontFamily,
            ),
          ),
        ],
      ),
    );
  }
}

class _StageSilhouette extends StatelessWidget {
  const _StageSilhouette();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 128,
      height: 72,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.32),
            width: 1.5,
          ),
          color: Colors.white.withValues(alpha: 0.05),
        ),
        child: Stack(
          children: [
            Center(
              child: CustomPaint(
                size: const Size(13, 16),
                painter: _PlayTrianglePainter(
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: SizedBox(
                height: 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: Colors.white.withValues(alpha: 0.22),
                      ),
                      const FractionallySizedBox(
                        widthFactor: 0.34,
                        alignment: Alignment.centerLeft,
                        child: ColoredBox(
                          color: Color(0x61FFFFFF),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayTrianglePainter extends CustomPainter {
  _PlayTrianglePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _PlayTrianglePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _StepChip extends StatelessWidget {
  const _StepChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          height: 1.3,
          color: Colors.white.withValues(alpha: 0.62),
        ),
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
    this.onRerun,
    this.rerunEnabled = true,
    this.onExpand,
  });

  final VideoItem item;
  final FluentTokens tokens;
  final Future<bool> Function(VideoItem item) onOpenSystem;
  final Future<bool> Function(VideoItem item) onSaveAs;
  final void Function(VideoItem item)? onRerun;
  final bool rerunEnabled;
  /// 窗内放大：打开 ContentDialog 预览（非系统全屏）。
  final VoidCallback? onExpand;

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
        setState(() {
          _error = VideoPlaybackErrors.streamFailed(
            msg,
            isRemote: _isHttp(_boundPath),
          );
        });
      }),
    ]);
  }

  Future<void> _retryPlayback() async {
    await _bind(widget.item, force: true);
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
        message: VideoPlaybackErrors.noAddress,
      );
      return;
    }
    if (path.startsWith('memory://')) {
      await _failBind(
        token: token,
        oldPlayer: oldPlayer,
        restoreBoundId: prevBoundId,
        restoreBoundPath: prevBoundPath,
        message: VideoPlaybackErrors.memoryOnly,
      );
      return;
    }

    final remote = _isHttp(path);
    Player? created;
    try {
      if (!remote) {
        final filePath =
            path.startsWith('file:') ? Uri.parse(path).toFilePath() : path;
        final f = File(filePath);
        if (!await f.exists()) {
          await _failBind(
            token: token,
            oldPlayer: oldPlayer,
            restoreBoundId: prevBoundId,
            restoreBoundPath: prevBoundPath,
            message: VideoPlaybackErrors.localMissing,
          );
          return;
        }
      }

      await _loadVolumePrefs();
      if (!mounted || token != _bindToken) {
        return;
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
        message: VideoPlaybackErrors.initFailed(e, isRemote: remote),
      );
    }
  }

  @override
  void dispose() {
    _bindToken++;
    _clearSubs();
    unawaited(VideoPlaybackPrefsWriter.instance.flush());
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
            spacing: 8,
            runSpacing: 6,
            children: [
              if (_error != null && _ready)
                VideoToolButton(
                  filled: true,
                  onPressed: _loading ? null : () => _retryPlayback(),
                  child: const Text('重试'),
                ),
              VideoToolButton(
                onPressed: () => widget.onSaveAs(widget.item),
                child: const Text('另存为…'),
              ),
              VideoToolButton(
                onPressed: () => widget.onOpenSystem(widget.item),
                child: const Text('系统打开'),
              ),
              if (widget.onRerun != null &&
                  (widget.item.prompt.trim().isNotEmpty ||
                      widget.item.referenceImages.isNotEmpty))
                VideoToolButton(
                  onPressed: widget.rerunEnabled
                      ? () => widget.onRerun!(widget.item)
                      : null,
                  child: const Text('用此提示重跑'),
                ),
              if (widget.onExpand != null)
                VideoToolButton(
                  onPressed: widget.onExpand,
                  child: const Text('窗内放大'),
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

    // 切换失败保留上一帧时，仍提示错误（重试在下方动作区）
    if (_error != null && _ready) {
      children.add(
        Align(
          alignment: Alignment.bottomCenter,
          child: ColoredBox(
            color: const Color(0xCC1A1A1A),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.danger,
                  fontFamily: tokens.fontFamily,
                  fontSize: 11,
                ),
              ),
            ),
          ),
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
    final volShown = (muted ? 0 : volume).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: SizedBox(
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
              child: _Scrubber(
                player: player,
                playedColor: tokens.primary,
                bufferedColor: tokens.inkMuted.withValues(alpha: 0.28),
                backgroundColor: tokens.canvas,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${fmt(position)} / ${fmt(duration)}',
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
              icon: muted ? FluentIcons.volume_disabled : FluentIcons.volume2,
              tooltip: muted ? '取消静音' : '音量 · 跨启动持久化',
              semanticLabel: muted ? '取消静音' : '静音',
              onPressed: () => onToggleMute(),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 72,
              child: Slider(
                value: muted ? 0 : volume,
                min: 0,
                max: 100,
                label: '$volShown%',
                onChanged: (v) => onVolumeChanged(v),
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
              onPressed: () => onFullscreen(),
            ),
          ],
        ),
      ),
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
