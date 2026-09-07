import 'package:flutter/foundation.dart';

/// 轻量生成运行时：begin / abort / end，防止旧 finally 清掉新任务。
class GenerationRuntime extends ChangeNotifier {
  String? _sessionId;
  Object? _token;
  VoidCallback? _cancelFn;

  String? get sessionId => _sessionId;

  bool get busy => _sessionId != null;

  bool isCurrent(String? activeId) =>
      _sessionId != null && _sessionId == activeId;

  /// 开始一路生成；[cancelFn] 用于 abort（如 close http.Client）。
  /// 返回本任务 token，供 [end] 校验。
  Object begin(String sessionId, VoidCallback cancelFn) {
    final token = Object();
    _sessionId = sessionId;
    _token = token;
    _cancelFn = cancelFn;
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
