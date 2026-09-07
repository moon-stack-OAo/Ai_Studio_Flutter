import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'chat_models.dart';

/// 单条消息 content 字符上限。
const int maxChatMessageChars = 100000;

/// 单会话最多保留消息条数。
const int maxChatMessagesPerSession = 200;

/// 最多保留会话数。
const int maxChatSessions = 40;

ChatMessage sanitizeChatMessage(
  ChatMessage msg, {
  int maxChars = maxChatMessageChars,
}) {
  final limit = maxChars < 1 ? 1 : maxChars;
  if (msg.content.length <= limit) return msg;
  return msg.copyWith(
    content:
        '${msg.content.substring(0, limit)}\n\n…（本地已截断，原长度 ${msg.content.length}）',
  );
}

ChatSession sanitizeChatSession(
  ChatSession session, {
  int maxMessages = maxChatMessagesPerSession,
  int maxMessageChars = maxChatMessageChars,
}) {
  final msgLimit = maxMessages < 1 ? 1 : maxMessages;
  var messages = List<ChatMessage>.from(session.messages);
  if (messages.length > msgLimit) {
    messages = messages.sublist(messages.length - msgLimit);
  }
  messages =
      messages.map((m) => sanitizeChatMessage(m, maxChars: maxMessageChars)).toList();
  return session.copyWith(messages: messages);
}

/// 按 updatedAt 保留最近会话；尽量保留 active。
List<ChatSession> capChatSessionCount(
  List<ChatSession> sessions,
  String? activeId, {
  int maxSessions = maxChatSessions,
}) {
  final limit = maxSessions < 1 ? 1 : maxSessions;
  if (sessions.length <= limit) return List<ChatSession>.from(sessions);

  final sorted = List<ChatSession>.from(sessions)
    ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
  final keep = <String>{};
  if (activeId != null && sorted.any((s) => s.id == activeId)) {
    keep.add(activeId);
  }
  for (var i = sorted.length - 1; i >= 0 && keep.length < limit; i--) {
    keep.add(sorted[i].id);
  }
  if (keep.length > limit) {
    keep.clear();
    for (var i = sorted.length - 1; i >= 0 && keep.length < limit; i--) {
      keep.add(sorted[i].id);
    }
  }
  return sessions.where((s) => keep.contains(s.id)).toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
}

ChatStoreSnapshot prepareChatPersistPayload(
  ChatStoreSnapshot snapshot, {
  int maxSessions = maxChatSessions,
  int maxMessagesPerSession = maxChatMessagesPerSession,
  int maxMessageChars = maxChatMessageChars,
}) {
  var sessions = snapshot.sessions
      .map(
        (s) => sanitizeChatSession(
          s,
          maxMessages: maxMessagesPerSession,
          maxMessageChars: maxMessageChars,
        ),
      )
      .toList();
  sessions = capChatSessionCount(
    sessions,
    snapshot.activeId,
    maxSessions: maxSessions,
  );
  var activeId = snapshot.activeId;
  if (sessions.isEmpty) {
    activeId = '';
  } else if (!sessions.any((s) => s.id == activeId)) {
    activeId = sessions.first.id;
  }
  return ChatStoreSnapshot(sessions: sessions, activeId: activeId);
}

abstract class ChatSessionStorage {
  Future<ChatStoreSnapshot> load();

  Future<void> save(ChatStoreSnapshot snapshot);
}

/// SharedPreferences：`core.chat_sessions.v1` → `{sessions, activeId}`。
class PrefsChatSessionStorage implements ChatSessionStorage {
  PrefsChatSessionStorage({SharedPreferences? prefs}) : _prefsOverride = prefs;

  static const prefsKey = 'core.chat_sessions.v1';

  final SharedPreferences? _prefsOverride;
  SharedPreferences? _prefs;

  Future<SharedPreferences> _ensurePrefs() async {
    return _prefs ??= _prefsOverride ?? await SharedPreferences.getInstance();
  }

  @override
  Future<ChatStoreSnapshot> load() async {
    final prefs = await _ensurePrefs();
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) {
      return const ChatStoreSnapshot(sessions: [], activeId: '');
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const ChatStoreSnapshot(sessions: [], activeId: '');
      }
      final listRaw = decoded['sessions'];
      final sessions = <ChatSession>[];
      if (listRaw is List) {
        for (final e in listRaw) {
          if (e is Map) {
            sessions.add(ChatSession.fromJson(Map<String, dynamic>.from(e)));
          }
        }
      }
      final prepared = prepareChatPersistPayload(
        ChatStoreSnapshot(
          sessions: sessions,
          activeId: decoded['activeId']?.toString() ?? '',
        ),
      );
      return prepared;
    } catch (_) {
      return const ChatStoreSnapshot(sessions: [], activeId: '');
    }
  }

  @override
  Future<void> save(ChatStoreSnapshot snapshot) async {
    final prefs = await _ensurePrefs();
    final prepared = prepareChatPersistPayload(snapshot);
    final payload = <String, dynamic>{
      'activeId': prepared.activeId,
      'sessions': prepared.sessions.map((s) => s.toJson()).toList(),
    };
    await prefs.setString(prefsKey, jsonEncode(payload));
  }
}

/// 内存存储（单元测试）。
class MemoryChatSessionStorage implements ChatSessionStorage {
  MemoryChatSessionStorage([ChatStoreSnapshot? initial])
      : _snapshot = initial ??
            const ChatStoreSnapshot(sessions: [], activeId: '');

  ChatStoreSnapshot _snapshot;

  @override
  Future<ChatStoreSnapshot> load() async => ChatStoreSnapshot(
        sessions: List<ChatSession>.from(_snapshot.sessions),
        activeId: _snapshot.activeId,
      );

  @override
  Future<void> save(ChatStoreSnapshot snapshot) async {
    final prepared = prepareChatPersistPayload(snapshot);
    _snapshot = ChatStoreSnapshot(
      sessions: List<ChatSession>.from(prepared.sessions),
      activeId: prepared.activeId,
    );
  }
}
