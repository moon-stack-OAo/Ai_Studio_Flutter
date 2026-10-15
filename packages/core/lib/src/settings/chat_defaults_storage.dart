import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'chat_defaults.dart';

/// 对话默认存储抽象。
abstract class ChatDefaultsStorage {
  Future<ChatDefaults> load();

  Future<void> save(ChatDefaults defaults);
}

/// SharedPreferences：`core.chat_defaults.v1` → JSON。
class PrefsChatDefaultsStorage implements ChatDefaultsStorage {
  PrefsChatDefaultsStorage({SharedPreferences? prefs}) : _prefsOverride = prefs;

  static const prefsKey = 'core.chat_defaults.v1';

  final SharedPreferences? _prefsOverride;
  SharedPreferences? _prefs;
  bool _reloadBeforeLoad = false;

  Future<SharedPreferences> _ensurePrefs() async {
    return _prefs ??= _prefsOverride ?? await SharedPreferences.getInstance();
  }

  @override
  Future<ChatDefaults> load() async {
    final prefs = await _ensurePrefs();
    if (_reloadBeforeLoad) {
      await prefs.reload();
      _reloadBeforeLoad = false;
    }
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) {
      return ChatDefaults.recommended;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return ChatDefaults.recommended;
      return ChatDefaults.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return ChatDefaults.recommended;
    }
  }

  @override
  Future<void> save(ChatDefaults defaults) async {
    final prefs = await _ensurePrefs();
    try {
      final saved = await prefs.setString(
        prefsKey,
        jsonEncode(defaults.sanitized().toJson()),
      );
      if (!saved) throw StateError('保存对话默认设置失败');
      _reloadBeforeLoad = false;
    } catch (_) {
      // SharedPreferences 会先修改缓存；失败后重新读取，避免 load 发布失败草稿。
      _reloadBeforeLoad = true;
      try {
        await prefs.reload();
        _reloadBeforeLoad = false;
      } catch (_) {
        // 保留原始保存异常，供界面提示并重试。
      }
      rethrow;
    }
  }
}

/// 内存存储（单元测试）。
class MemoryChatDefaultsStorage implements ChatDefaultsStorage {
  MemoryChatDefaultsStorage([ChatDefaults? initial])
    : _defaults = (initial ?? ChatDefaults.recommended).sanitized();

  ChatDefaults _defaults;

  ChatDefaults get current => _defaults;

  @override
  Future<ChatDefaults> load() async => _defaults;

  @override
  Future<void> save(ChatDefaults defaults) async {
    _defaults = defaults.sanitized();
  }
}
