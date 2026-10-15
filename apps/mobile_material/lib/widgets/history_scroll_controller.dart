import 'dart:async';

import 'package:design_material/design_material.dart';
import 'package:flutter/widgets.dart';

/// 生图/生视频保留输入区在上，滚动后复核懒加载历史的实际底部。
class HistoryScrollController extends ScrollController {
  int _revision = 0;
  int? _runningRevision;
  bool _pending = false;
  bool _disposed = false;

  void scrollToBottom() {
    _pending = true;
    _schedule(++_revision);
  }

  void cancelPendingScroll() {
    _pending = false;
    _revision++;
  }

  bool handleScrollStart(ScrollStartNotification notification) {
    if (notification.depth == 0 && notification.dragDetails != null) {
      cancelPendingScroll();
    }
    return false;
  }

  @override
  void attach(ScrollPosition position) {
    super.attach(position);
    if (_pending) _schedule(_revision);
  }

  void _schedule(int revision) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isCurrent(revision)) unawaited(_settleBottom(revision));
    });
  }

  bool _isCurrent(int revision) =>
      !_disposed && _pending && revision == _revision;

  Future<void> _settleBottom(int revision) async {
    if (_runningRevision == revision) return;
    _runningRevision = revision;
    try {
      while (_isCurrent(revision) && hasClients) {
        if (position.extentAfter < 0.5) {
          _pending = false;
          return;
        }
        await animateTo(
          position.maxScrollExtent,
          duration: MaterialMotion.micro,
          curve: MaterialMotion.standard,
        );
        if (!_isCurrent(revision)) return;
        // 滚动可能构建新的大卡片并改变 maxScrollExtent，下一帧再检查。
        await WidgetsBinding.instance.endOfFrame;
      }
    } finally {
      if (_runningRevision == revision) _runningRevision = null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    cancelPendingScroll();
    super.dispose();
  }
}
