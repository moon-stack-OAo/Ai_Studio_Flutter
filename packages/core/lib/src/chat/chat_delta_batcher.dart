import 'dart:async';

/// 首段立即发布，随后按时间窗口合批；关闭后拒绝迟到的网络回调。
class ChatDeltaBatcher {
  ChatDeltaBatcher({required this.onFlush, required this.interval});

  final void Function(String content) onFlush;
  final Duration interval;
  final StringBuffer _content = StringBuffer();
  Timer? _timer;
  bool _started = false;
  bool _dirty = false;
  bool _closed = false;

  void add(String delta) {
    if (_closed || delta.isEmpty) return;
    _content.write(delta);
    _dirty = true;
    if (!_started) {
      _started = true;
      _flush();
    }
    _timer ??= Timer(interval, _tick);
  }

  void _tick() {
    _timer = null;
    if (_closed) return;
    _flush();
    // 保持窗口边界，空闲时不继续排 timer。
  }

  void _flush() {
    if (!_dirty) return;
    _dirty = false;
    onFlush(_content.toString());
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    _timer = null;
    _flush();
  }
}
