import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

/// 抑制 Windows `video_player_win` 播完后首尾帧来回跳，并用墙钟驱动进度 UI。
///
/// - 播完闪跳：`completed → seekTo(duration)` 在 Win 上会强制续播。
/// - 进度滞后：原生 `position` 常落后；播放中跟墙钟。
/// - 开头卡 0：`play()` 后短暂 `!isPlaying` 用宽限期保住墙钟。
/// - 画面停、进度仍跑：宽限期后平台已停则冻结；近片尾钉死并清意图。
/// - 暂停后再点无效：意图以 [_userWantsPlay] 为准。
class VideoPlaybackGuard extends ChangeNotifier {
  VideoPlaybackGuard(this.controller) {
    controller.addListener(_onControllerTick);
    final v = controller.value;
    if (v.isInitialized) {
      _basePosition = v.position;
      _speed = v.playbackSpeed <= 0 ? 1.0 : v.playbackSpeed;
      if (v.isPlaying) {
        _baseAt = DateTime.now();
        _userWantsPlay = true;
        _wantPlaySince = DateTime.now();
        _startUiTimer();
      }
    }
  }

  static const Duration _endEpsilon = Duration(milliseconds: 60);
  /// 平台已停时放宽判尾，避免墙钟还差一点就空跑。
  static const Duration _stoppedEndEpsilon = Duration(milliseconds: 350);
  static const Duration _uiTick = Duration(milliseconds: 16);
  static const Duration _playGrace = Duration(milliseconds: 450);

  final VideoPlayerController controller;

  bool _pinningEnd = false;
  bool _handling = false;
  bool _scrubbing = false;
  bool _disposed = false;
  bool _userWantsPlay = false;
  DateTime? _wantPlaySince;

  Duration _basePosition = Duration.zero;
  DateTime? _baseAt;
  double _speed = 1.0;
  Timer? _uiTimer;

  bool get pinningEnd => _pinningEnd;

  bool get uiPlaying => !_pinningEnd && _userWantsPlay;

  bool get _inPlayGrace {
    final since = _wantPlaySince;
    if (!_userWantsPlay || since == null) return false;
    return DateTime.now().difference(since) < _playGrace;
  }

  @override
  void dispose() {
    _disposed = true;
    _uiTimer?.cancel();
    controller.removeListener(_onControllerTick);
    super.dispose();
  }

  void _onControllerTick() {
    if (_disposed || _handling || _scrubbing) return;
    final v = controller.value;
    if (!v.isInitialized) return;

    _speed = v.playbackSpeed <= 0 ? 1.0 : v.playbackSpeed;

    if (_pinningEnd) {
      if (v.isPlaying) {
        _handling = true;
        controller.pause().whenComplete(() {
          _handling = false;
        });
      }
      return;
    }

    if (v.isCompleted) {
      _pinToEnd(v.duration, pauseIfPlaying: v.isPlaying);
      return;
    }

    if (!_userWantsPlay && v.isPlaying) {
      _handling = true;
      controller.pause().whenComplete(() {
        _handling = false;
      });
      return;
    }

    if (_userWantsPlay) {
      _onWantPlayTick(v);
      return;
    }

    _freezeClock();
    if (v.position > _basePosition) {
      _basePosition = v.position;
    }
    _stopUiTimer();
    _emit();
  }

  void _onWantPlayTick(VideoPlayerValue v) {
    if (_isAtEnd(v.position, v.duration) ||
        _isAtEnd(estimatedPosition, v.duration, epsilon: _stoppedEndEpsilon)) {
      _pinToEnd(v.duration, pauseIfPlaying: v.isPlaying);
      return;
    }

    if (v.isPlaying) {
      if (_baseAt == null) {
        _basePosition =
            v.position > _basePosition ? v.position : _basePosition;
        _baseAt = DateTime.now();
      }
      _startUiTimer();
      return;
    }

    // 缓冲：画面卡住，冻结进度。
    if (v.isBuffering) {
      _freezeClock();
      _emit();
      return;
    }

    // play 握手宽限期：允许短暂 !isPlaying，墙钟继续。
    if (_inPlayGrace) {
      _baseAt ??= DateTime.now();
      _startUiTimer();
      return;
    }

    // 宽限期后平台已停：冻结；近尾钉死；否则视为停住（清意图，按钮变播放）。
    _handlePlatformStopped(v);
  }

  void _handlePlatformStopped(VideoPlayerValue v) {
    _freezeClock();
    if (v.isCompleted ||
        _isAtEnd(v.position, v.duration, epsilon: _stoppedEndEpsilon) ||
        _isAtEnd(estimatedPosition, v.duration, epsilon: _stoppedEndEpsilon)) {
      _pinToEnd(v.duration, pauseIfPlaying: false);
      return;
    }
    _userWantsPlay = false;
    _wantPlaySince = null;
    _stopUiTimer();
    _emit();
  }

  void _freezeClock() {
    if (_baseAt != null) {
      _basePosition = estimatedPosition;
      _baseAt = null;
    }
  }

  void _pinToEnd(Duration duration, {required bool pauseIfPlaying}) {
    _pinningEnd = true;
    _userWantsPlay = false;
    _wantPlaySince = null;
    _basePosition = duration;
    _baseAt = null;
    _stopUiTimer();
    _emit();
    if (pauseIfPlaying) {
      _handling = true;
      controller.pause().whenComplete(() {
        _handling = false;
      });
    }
  }

  bool _isAtEnd(
    Duration position,
    Duration duration, {
    Duration epsilon = _endEpsilon,
  }) {
    if (duration <= Duration.zero) return false;
    return position >= duration - epsilon;
  }

  Duration get estimatedPosition {
    final v = controller.value;
    if (!v.isInitialized) return Duration.zero;
    if (_pinningEnd || v.isCompleted) return v.duration;

    var pos = _basePosition;
    final startedAt = _baseAt;
    if (startedAt != null) {
      final elapsed = DateTime.now().difference(startedAt);
      final advanceMs = (elapsed.inMilliseconds * _speed).round();
      pos = _basePosition + Duration(milliseconds: advanceMs);
    }

    final d = v.duration;
    if (d > Duration.zero && pos > d) return d;
    if (pos < Duration.zero) return Duration.zero;
    return pos;
  }

  Duration displayPosition(VideoPlayerValue v) => estimatedPosition;

  double progressFraction(VideoPlayerValue v) {
    final d = v.duration.inMilliseconds;
    if (d <= 0) return 0;
    if (_pinningEnd || v.isCompleted) return 1;
    return (estimatedPosition.inMilliseconds / d).clamp(0.0, 1.0);
  }

  void notePlayStarted() {
    if (_disposed || _pinningEnd) return;
    final v = controller.value;
    if (!v.isInitialized) return;
    _userWantsPlay = true;
    _wantPlaySince = DateTime.now();
    _speed = v.playbackSpeed <= 0 ? 1.0 : v.playbackSpeed;
    if (_baseAt == null) {
      _basePosition = estimatedPosition;
      _baseAt = DateTime.now();
    }
    _startUiTimer();
    _emit();
  }

  Future<void> togglePlayPause() async {
    final v = controller.value;
    if (!v.isInitialized) return;

    if (uiPlaying) {
      _userWantsPlay = false;
      _wantPlaySince = null;
      _freezeClock();
      _stopUiTimer();
      _emit();
      _handling = true;
      try {
        await controller.pause();
      } finally {
        _handling = false;
      }
      _emit();
      return;
    }

    final restart = _pinningEnd ||
        v.isCompleted ||
        _isAtEnd(estimatedPosition, v.duration, epsilon: _stoppedEndEpsilon);
    _pinningEnd = false;
    _userWantsPlay = true;
    _wantPlaySince = DateTime.now();
    if (restart) {
      _handling = true;
      try {
        await controller.seekTo(Duration.zero);
      } finally {
        _handling = false;
      }
      _basePosition = Duration.zero;
      _baseAt = DateTime.now();
    } else if (_baseAt == null) {
      _basePosition = estimatedPosition;
      _baseAt = DateTime.now();
    }
    _startUiTimer();
    _emit();
    unawaited(controller.play());
  }

  Future<void> seekFraction(double fraction, {required bool resume}) async {
    final v = controller.value;
    if (!v.isInitialized) return;
    final d = v.duration;
    if (d <= Duration.zero) return;
    final clamped = fraction.clamp(0.0, 1.0);
    final target = Duration(milliseconds: (d.inMilliseconds * clamped).round());
    _scrubbing = true;
    _pinningEnd = false;
    _stopUiTimer();
    try {
      await controller.seekTo(target);
      _basePosition = target;
      _baseAt = null;
      _emit();
      if (!resume || _isAtEnd(target, d)) {
        _userWantsPlay = false;
        _wantPlaySince = null;
        await controller.pause();
        if (_isAtEnd(target, d)) {
          _pinToEnd(d, pauseIfPlaying: false);
        } else {
          _emit();
        }
      } else {
        _userWantsPlay = true;
        _wantPlaySince = DateTime.now();
        _baseAt = DateTime.now();
        _startUiTimer();
        _emit();
        unawaited(controller.play());
      }
    } finally {
      _scrubbing = false;
    }
  }

  void _startUiTimer() {
    if (_uiTimer != null) return;
    _uiTimer = Timer.periodic(_uiTick, (_) {
      if (_disposed || _pinningEnd || _scrubbing) return;
      final v = controller.value;
      if (!v.isInitialized) {
        _stopUiTimer();
        return;
      }
      if (!_userWantsPlay) {
        _stopUiTimer();
        return;
      }

      if (v.isCompleted ||
          _isAtEnd(v.position, v.duration) ||
          _isAtEnd(estimatedPosition, v.duration)) {
        _pinToEnd(v.duration, pauseIfPlaying: v.isPlaying);
        return;
      }

      if (!v.isPlaying) {
        if (v.isBuffering) {
          _freezeClock();
          _emit();
          return;
        }
        if (_inPlayGrace) {
          _baseAt ??= DateTime.now();
          _emit();
          return;
        }
        _handlePlatformStopped(v);
        return;
      }

      _baseAt ??= DateTime.now();
      _emit();
    });
  }

  void _stopUiTimer() {
    _uiTimer?.cancel();
    _uiTimer = null;
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }
}
