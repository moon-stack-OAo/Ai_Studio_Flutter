import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_attach.dart';
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
  final cappedAtt = sanitizeChatAttachments(msg.attachments);
  final contentOk = msg.content.length <= limit;
  final attOk = cappedAtt.length == msg.attachments.length;
  if (contentOk && attOk) return msg;
  return msg.copyWith(
    content: contentOk
        ? null
        : '${msg.content.substring(0, limit)}\n\n…（本地已截断，原长度 ${msg.content.length}）',
    attachments: attOk ? null : cappedAtt,
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

/// 串行写入；在途写入期间仅保留最新待写快照。
/// 被合并请求的等待者随实际覆盖它的写入完成；失败只影响该批等待者。
class ChatSnapshotWriter {
  ChatSnapshotWriter(this._write);

  final Future<void> Function(ChatStoreSnapshot) _write;
  ChatStoreSnapshot? _pending;
  List<Completer<void>> _waiters = [];
  bool _running = false;

  Future<void> save(ChatStoreSnapshot snapshot) {
    final waiter = Completer<void>();
    _pending = snapshot;
    _waiters.add(waiter);
    if (!_running) {
      _running = true;
      scheduleMicrotask(_drain);
    }
    return waiter.future;
  }

  Future<void> _drain() async {
    while (_pending != null) {
      final snapshot = _pending!;
      final waiters = _waiters;
      _pending = null;
      _waiters = [];
      try {
        await _write(snapshot);
        for (final waiter in waiters) {
          waiter.complete();
        }
      } catch (error, stack) {
        for (final waiter in waiters) {
          waiter.completeError(error, stack);
        }
      }
    }
    _running = false;
  }
}

// 顶层函数仅接收纯数据模型，不捕获 prefs、平台通道或 repository。
String _encodeChatSnapshot(ChatStoreSnapshot snapshot) {
  final prepared = prepareChatPersistPayload(snapshot);
  return jsonEncode({
    'activeId': prepared.activeId,
    'sessions': prepared.sessions.map((s) => s.toJson()).toList(),
  });
}

bool _needsBackgroundEncoding(ChatStoreSnapshot snapshot) {
  var chars = 0;
  var messages = 0;
  for (final session in snapshot.sessions) {
    chars += session.title.length + (session.overrides.systemPrompt?.length ?? 0);
    if (chars >= 64 * 1024) return true;
    for (final message in session.messages) {
      if (++messages >= 256) return true;
      chars += message.content.length;
      for (final call in message.toolCalls) {
        chars += call.arguments.length;
      }
      for (final attachment in message.attachments) {
        chars += attachment.src.length;
      }
      for (final skill in message.appliedSkills) {
        chars += skill.prompt.length + skill.rules.length;
      }
      if (chars >= 64 * 1024) return true;
    }
  }
  return false;
}

/// SharedPreferences：`core.chat_sessions.v1` → `{sessions, activeId}`。
class PrefsChatSessionStorage implements ChatSessionStorage {
  PrefsChatSessionStorage({SharedPreferences? prefs}) : _prefsOverride = prefs;

  static const prefsKey = 'core.chat_sessions.v1';

  final SharedPreferences? _prefsOverride;
  SharedPreferences? _prefs;
  late final ChatSnapshotWriter _writer = ChatSnapshotWriter(_save);

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
  Future<void> save(ChatStoreSnapshot snapshot) => _writer.save(snapshot);

  Future<void> _save(ChatStoreSnapshot snapshot) async {
    final prefs = await _ensurePrefs();
    final payload = _needsBackgroundEncoding(snapshot)
        ? await compute(_encodeChatSnapshot, snapshot)
        : _encodeChatSnapshot(snapshot);
    if (!await prefs.setString(prefsKey, payload)) {
      throw StateError('保存对话失败');
    }
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
