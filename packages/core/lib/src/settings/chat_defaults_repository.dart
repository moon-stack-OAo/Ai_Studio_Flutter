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

  bool get isLoaded => _loaded;
  bool get isLoading => _loading;
  String? get lastError => _lastError;

  ChatDefaults get defaults => _defaults;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _lastError = null;
    notifyListeners();
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
  }

  Future<void> save(ChatDefaults next) async {
    final sanitized = next.sanitized();
    _defaults = sanitized;
    notifyListeners();
    try {
      await _storage.save(sanitized);
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      rethrow;
    }
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
    return save(
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
    );
  }

  Future<void> resetToRecommended() => save(ChatDefaults.recommended);
}
