import 'package:flutter/foundation.dart';

import '../util/id.dart';
import 'chat_models.dart';
import 'chat_session_storage.dart';

/// 对话会话仓库：CRUD、activeId、流式更新、撤回、持久化。
class ChatSessionRepository extends ChangeNotifier {
  ChatSessionRepository({required ChatSessionStorage storage})
      : _storage = storage;

  final ChatSessionStorage _storage;

  List<ChatSession> _sessions = const [];
  String _activeId = '';
  bool _loaded = false;
  bool _loading = false;
  String? _lastError;

  bool get isLoaded => _loaded;
  bool get isLoading => _loading;
  String? get lastError => _lastError;

  List<ChatSession> get sessions => List.unmodifiable(_sessions);

  /// 按 updatedAt 降序。
  List<ChatSession> get sortedSessions {
    final list = List<ChatSession>.from(_sessions);
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  String get activeId => _activeId;

  ChatSession? get activeSession {
    if (_sessions.isEmpty) return null;
    for (final s in _sessions) {
      if (s.id == _activeId) return s;
    }
    return _sessions.first;
  }

  int _now() => DateTime.now().millisecondsSinceEpoch;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _lastError = null;
    notifyListeners();
    try {
      final snap = await _storage.load();
      _sessions = List<ChatSession>.from(snap.sessions);
      _activeId = snap.activeId;
      if (_sessions.isEmpty) {
        final session = _newSession();
        _sessions = [session];
        _activeId = session.id;
        await _persist();
      } else if (!_sessions.any((s) => s.id == _activeId)) {
        _activeId = _sessions.first.id;
        await _persist();
      }
      _loaded = true;
    } catch (e) {
      _lastError = '加载会话失败：$e';
      if (_sessions.isEmpty) {
        final session = _newSession();
        _sessions = [session];
        _activeId = session.id;
        _loaded = true;
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    await _storage.save(
      ChatStoreSnapshot(sessions: _sessions, activeId: _activeId),
    );
  }

  ChatSession _newSession([String title = '新对话']) {
    final now = _now();
    return ChatSession(
      id: createId('chat'),
      title: title,
      createdAt: now,
      updatedAt: now,
    );
  }

  int _indexOf(String id) => _sessions.indexWhere((s) => s.id == id);

  ChatSession? _find(String id) {
    for (final s in _sessions) {
      if (s.id == id) return s;
    }
    return null;
  }

  void _replace(int index, ChatSession next) {
    final list = List<ChatSession>.from(_sessions);
    list[index] = next;
    _sessions = list;
  }

  Future<ChatSession> createSession({String title = '新对话'}) async {
    final session = _newSession(title);
    _sessions = [session, ..._sessions];
    _activeId = session.id;
    await _persist();
    notifyListeners();
    return session;
  }

  Future<void> setActive(String id) async {
    if (!_sessions.any((s) => s.id == id)) return;
    _activeId = id;
    await _persist();
    notifyListeners();
  }

  Future<void> renameSession(String id, String title) async {
    final index = _indexOf(id);
    if (index < 0) return;
    final t = title.trim().isEmpty ? '新对话' : title.trim();
    _replace(
      index,
      _sessions[index].copyWith(title: t, updatedAt: _now()),
    );
    await _persist();
    notifyListeners();
  }

  Future<void> setSessionOverrides(String id, ChatOverrides overrides) async {
    final index = _indexOf(id);
    if (index < 0) return;
    _replace(
      index,
      _sessions[index].copyWith(overrides: overrides, updatedAt: _now()),
    );
    await _persist();
    notifyListeners();
  }

  Future<void> removeSession(String id) async {
    _sessions = _sessions.where((s) => s.id != id).toList();
    if (_sessions.isEmpty) {
      final session = _newSession();
      _sessions = [session];
      _activeId = session.id;
    } else if (_activeId == id) {
      _activeId = _sessions.first.id;
    }
    await _persist();
    notifyListeners();
  }

  Future<void> clearMessages(String id) async {
    final index = _indexOf(id);
    if (index < 0) return;
    _replace(
      index,
      _sessions[index].copyWith(messages: const [], updatedAt: _now()),
    );
    await _persist();
    notifyListeners();
  }

  /// 用快照整体替换（导入备份用）；空列表时自动建一条空会话。
  Future<void> replaceAll(ChatStoreSnapshot snapshot) async {
    var sessions = List<ChatSession>.from(snapshot.sessions);
    var activeId = snapshot.activeId;
    if (sessions.isEmpty) {
      final session = _newSession();
      sessions = [session];
      activeId = session.id;
    } else if (!sessions.any((s) => s.id == activeId)) {
      activeId = sessions.first.id;
    }
    _sessions = sessions;
    _activeId = activeId;
    _loaded = true;
    await _persist();
    notifyListeners();
  }

  /// 清除全部对话会话（保留一条空会话）。幂等。
  Future<void> clearAllSessions() async {
    final session = _newSession();
    _sessions = [session];
    _activeId = session.id;
    await _persist();
    notifyListeners();
  }

  /// 追加消息；首条 user 截 24 字作 title。
  Future<ChatMessage?> appendMessage(
    String sessionId, {
    required ChatRole role,
    required String content,
    bool streaming = false,
    bool stopped = false,
    bool error = false,
    String? errorMessage,
    String? model,
    int? latencyMs,
    String? id,
    int? createdAt,
  }) async {
    final index = _indexOf(sessionId);
    if (index < 0) return null;
    final session = _sessions[index];
    final item = ChatMessage(
      id: id ?? createId('msg'),
      createdAt: createdAt ?? _now(),
      role: role,
      content: content,
      streaming: streaming,
      stopped: stopped,
      error: error,
      errorMessage: errorMessage,
      model: model,
      latencyMs: latencyMs,
    );
    var title = session.title;
    if (title == '新对话' &&
        role == ChatRole.user &&
        content.trim().isNotEmpty) {
      final slice = content.trim();
      title = slice.length <= 24 ? slice : slice.substring(0, 24);
    }
    _replace(
      index,
      session.copyWith(
        messages: [...session.messages, item],
        title: title,
        updatedAt: _now(),
      ),
    );
    await _persist();
    notifyListeners();
    return item;
  }

  /// 更新消息；流式时可 [persist]=false 降低写入频率。
  Future<void> updateMessage(
    String sessionId,
    String messageId, {
    String? content,
    bool? streaming,
    bool? stopped,
    bool? error,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? model,
    bool clearModel = false,
    int? latencyMs,
    bool clearLatencyMs = false,
    bool persist = true,
  }) async {
    final index = _indexOf(sessionId);
    if (index < 0) return;
    final session = _sessions[index];
    final msgIndex = session.messages.indexWhere((m) => m.id == messageId);
    if (msgIndex < 0) return;
    final msgs = List<ChatMessage>.from(session.messages);
    msgs[msgIndex] = msgs[msgIndex].copyWith(
      content: content,
      streaming: streaming,
      stopped: stopped,
      error: error,
      errorMessage: errorMessage,
      clearErrorMessage: clearErrorMessage,
      model: model,
      clearModel: clearModel,
      latencyMs: latencyMs,
      clearLatencyMs: clearLatencyMs,
    );
    _replace(
      index,
      session.copyWith(messages: msgs, updatedAt: _now()),
    );
    if (persist) await _persist();
    notifyListeners();
  }

  /// 追加流式内容到指定 assistant 消息。
  Future<void> appendStreamingContent(
    String sessionId,
    String messageId,
    String delta, {
    bool persist = false,
  }) async {
    final session = _find(sessionId);
    if (session == null) return;
    ChatMessage? msg;
    for (final m in session.messages) {
      if (m.id == messageId) {
        msg = m;
        break;
      }
    }
    if (msg == null) return;
    await updateMessage(
      sessionId,
      messageId,
      content: msg.content + delta,
      streaming: true,
      persist: persist,
    );
  }

  /// 标记停止（用户取消）。
  Future<void> markStopped(String sessionId, String messageId) async {
    await updateMessage(
      sessionId,
      messageId,
      streaming: false,
      stopped: true,
      persist: true,
    );
  }

  /// 撤回：删最后一对 user+assistant，或指定 user 消息及其后 assistant。
  /// 返回被删 id；无操作返回 null。
  Future<List<String>?> recallUserMessage(
    String sessionId, {
    String? userMessageId,
  }) async {
    final index = _indexOf(sessionId);
    if (index < 0) return null;
    final session = _sessions[index];
    final msgs = session.messages;
    if (msgs.isEmpty) return null;

    int idx;
    if (userMessageId != null) {
      idx = msgs.indexWhere((m) => m.id == userMessageId);
      if (idx < 0 || msgs[idx].role != ChatRole.user) return null;
    } else {
      idx = -1;
      for (var i = msgs.length - 1; i >= 0; i--) {
        if (msgs[i].role == ChatRole.user) {
          idx = i;
          break;
        }
      }
      if (idx < 0) return null;
    }

    final removedIds = <String>[msgs[idx].id];
    var deleteCount = 1;
    if (idx + 1 < msgs.length && msgs[idx + 1].role == ChatRole.assistant) {
      removedIds.add(msgs[idx + 1].id);
      deleteCount = 2;
    }
    final nextMsgs = List<ChatMessage>.from(msgs)..removeRange(idx, idx + deleteCount);
    _replace(
      index,
      session.copyWith(messages: nextMsgs, updatedAt: _now()),
    );
    await _persist();
    notifyListeners();
    return removedIds;
  }
}
