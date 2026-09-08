import 'package:flutter/foundation.dart';

/// 轻量生成运行时：begin / abort / end，防止旧 finally 清掉新任务。
///
/// 全局单例跨对话 / 生图 / 生视频共用；[begin] 若已有进行中任务，
/// 会先调用旧 [cancelFn] 再接管，避免旧请求无法 abort。
class GenerationRuntime extends ChangeNotifier {
  String? _sessionId;
  Object? _token;
  VoidCallback? _cancelFn;

  String? get sessionId => _sessionId;

  bool get busy => _sessionId != null;

  bool isCurrent(String? activeId) =>
      _sessionId != null && _sessionId == activeId;

  /// 开始一路生成；[cancelFn] 用于 abort（如 close http.Client）。
  ///
  /// 若当前已 busy，先调用旧 cancel（此时新 token 已安装，旧 [end]
  /// 不会清掉新任务），再接管。返回本任务 token，供 [end] 校验。
  Object begin(String sessionId, VoidCallback cancelFn) {
    final previousCancel = _cancelFn;
    final token = Object();
    _sessionId = sessionId;
    _token = token;
    _cancelFn = cancelFn;
    // 先安装新 token，再 abort 旧任务，避免旧 finally 误清新状态。
    previousCancel?.call();
    notifyListeners();
    return token;
  }

  /// 仅当仍是同一会话且（可选）同一 token 时清理。
  void end(String sessionId, [Object? token]) {
    if (token != null && !identical(_token, token)) return;
    if (_sessionId != sessionId) return;
    _sessionId = null;
    _token = null;
    _cancelFn = null;
    notifyListeners();
  }

  void abort([String? sessionId]) {
    if (sessionId != null && _sessionId != sessionId) return;
    final fn = _cancelFn;
    fn?.call();
  }

  /// 删除指定会话时：若正在生成该会话则 abort。
  void abortIfSession(String sessionId) {
    if (_sessionId == sessionId) {
      abort(sessionId);
    }
  }
}
