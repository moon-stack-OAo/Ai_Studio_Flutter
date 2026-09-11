import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:media_kit/media_kit.dart';

/// 基于 media_kit 的成片抽帧（JPEG），注入 [VideoPosterService]。
///
/// 不依赖 `media_kit_video` 的纹理控件；静音打开、seek 后 `screenshot`。
class MediaKitVideoFrameExtractor implements VideoFrameExtractor {
  /// 串行化：避免多路 Player 同时抢解码资源。
  static Future<void> _tail = Future<void>.value();

  @override
  Future<Uint8List?> extractJpeg(
    String videoPath, {
    Duration at = const Duration(milliseconds: 400),
  }) {
    final completer = Completer<Uint8List?>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await _extractOnce(videoPath, at: at));
      } catch (_) {
        completer.complete(null);
      }
    });
    return completer.future;
  }

  Future<Uint8List?> _extractOnce(
    String videoPath, {
    required Duration at,
  }) async {
    final path = videoPath.trim();
    if (path.isEmpty) return null;
    if (!File(path).existsSync()) return null;

    final player = Player(
      configuration: const PlayerConfiguration(muted: true),
    );
    try {
      await player.setVolume(0);
      final uri = path.startsWith('file:') ? path : Uri.file(path).toString();
      await player.open(Media(uri), play: false);

      final ready = await _waitForDecodable(player);
      if (!ready) return null;

      final duration = player.state.duration;
      var seekTo = at;
      if (duration > Duration.zero) {
        final maxAt = duration > const Duration(seconds: 1)
            ? const Duration(milliseconds: 800)
            : Duration(
                milliseconds: (duration.inMilliseconds * 0.2).round(),
              );
        if (seekTo > maxAt) seekTo = maxAt;
        if (seekTo >= duration) {
          seekTo = Duration(
            milliseconds: (duration.inMilliseconds * 0.1).round(),
          );
        }
      }
      if (seekTo > Duration.zero) {
        try {
          await player.seek(seekTo);
          await Future<void>.delayed(const Duration(milliseconds: 150));
        } catch (_) {}
      }

      for (var i = 0; i < 5; i++) {
        final bytes = await player.screenshot(format: 'image/jpeg');
        if (bytes != null && bytes.isNotEmpty) return bytes;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      return null;
    } finally {
      try {
        await player.dispose();
      } catch (_) {}
    }
  }

  Future<bool> _waitForDecodable(Player player) async {
    if ((player.state.width ?? 0) > 0) return true;
    if (player.state.duration > Duration.zero) return true;

    final completer = Completer<bool>();
    StreamSubscription<int?>? widthSub;
    StreamSubscription<Duration>? durSub;
    Timer? timer;

    void finish(bool ok) {
      if (completer.isCompleted) return;
      completer.complete(ok);
      unawaited(widthSub?.cancel() ?? Future<void>.value());
      unawaited(durSub?.cancel() ?? Future<void>.value());
      timer?.cancel();
    }

    widthSub = player.stream.width.listen((w) {
      if (w != null && w > 0) finish(true);
    });
    durSub = player.stream.duration.listen((d) {
      if (d > Duration.zero) finish(true);
    });
    timer = Timer(const Duration(seconds: 8), () => finish(false));

    return completer.future;
  }
}
