import 'package:flutter/foundation.dart';

import 'chat_defaults.dart';
import 'chat_defaults_storage.dart';

/// 对话默认仓库（ChangeNotifier）。
class ChatDefaultsRepository extends ChangeNotifier {
  ChatDefaultsRepository({required ChatDefaultsStorage storage})
    : _storage = storage;

  final ChatDefaultsStorage _storage;

  ChatDefaults _defaults = ChatDefaults.recommended;
  bool _loaded = false;
  bool _loading = false;
  String? _lastError;
  Future<void> _pendingOperation = Future<void>.value();

  bool get isLoaded => _loaded;
  bool get isLoading => _loading;
  String? get lastError => _lastError;

  ChatDefaults get defaults => _defaults;

  Future<void> load() {
    if (_loading) return Future<void>.value();
    _loading = true;
    _lastError = null;
    final operation = _enqueue(() async {
      _lastError = null;
      try {
        _defaults = (await _storage.load()).sanitized();
        _loaded = true;
      } catch (e) {
        _lastError = e.toString();
        _defaults = ChatDefaults.recommended;
        _loaded = true;
      } finally {
        _loading = false;
        notifyListeners();
      }
    });
    notifyListeners();
    return operation;
  }

  // 读写按调用顺序执行；失败仅传给对应调用者，不阻断后续操作。
  Future<void> _enqueue(Future<void> Function() action) {
    final operation = _pendingOperation.then((_) => action());
    _pendingOperation = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  /// 持久化成功后才发布配置；失败时保留原配置并向调用者抛出异常。
  Future<void> save(ChatDefaults next) => _enqueue(() => _save(next));

  Future<void> _save(ChatDefaults next) async {
    final sanitized = next.sanitized();
    try {
      await _storage.save(sanitized);
      _defaults = sanitized;
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      rethrow;
    }
    notifyListeners();
  }

  Future<void> update({
    double? temperature,
    String? systemPrompt,
    int? maxTokens,
    int? apiTimeoutMs,
    bool? contextTrimEnabled,
    int? contextMaxTurns,
    bool? contextMaxCharsEnabled,
    int? contextMaxChars,
  }) {
    // 等待前序操作完成后再合并，避免并发局部更新丢失前一次成功修改。
    return _enqueue(
      () => _save(
        _defaults.copyWith(
          temperature: temperature,
          systemPrompt: systemPrompt,
          maxTokens: maxTokens,
          apiTimeoutMs: apiTimeoutMs,
          contextTrimEnabled: contextTrimEnabled,
          contextMaxTurns: contextMaxTurns,
          contextMaxCharsEnabled: contextMaxCharsEnabled,
          contextMaxChars: contextMaxChars,
        ),
      ),
    );
  }

  Future<void> resetToRecommended() => save(ChatDefaults.recommended);
}
