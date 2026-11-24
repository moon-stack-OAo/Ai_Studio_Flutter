import 'dart:async';

import 'package:flutter/foundation.dart';

import '../settings/history_snapshot_store.dart';
import '../settings/asset_reference_guard.dart';

import '../image/image_asset_store.dart';
import '../image/image_models.dart';
import '../mcp/mcp_models.dart';
import '../prompt/custom_skills.dart';
import '../util/id.dart';
import 'chat_attach.dart';
import 'chat_models.dart';
import 'chat_session_storage.dart';

/// 流式 content 刷新 UI 的最小间隔（合批 delta，降低 Markdown/列表重建频率）。
const Duration kChatStreamingUiMinInterval = Duration(milliseconds: 64);

/// 对话会话仓库：CRUD、activeId、流式更新、撤回、持久化、CHAT-ATTACH 资产。
class ChatSessionRepository extends ChangeNotifier {
  ChatSessionRepository({
    required ChatSessionStorage storage,
    AssetReferenceGuard? assetReferences,
    ImageAssetStore? attachmentStore,
  }) : _storage = storage,
       _attachmentStore = attachmentStore ?? MemoryImageAssetStore(),
       _assetReferences = assetReferences {
    assetReferences?.register(this, () {
      if (!_loaded || _loading || writesBlocked || _lastError != null) {
        throw const HistoryStorageException();
      }
      return {
        for (final s in _sessions)
          for (final m in s.messages)
            for (final ref in m.attachments)
              if (ref.type == ImageRefType.file) ref.src,
      };
    });
  }

  final AssetReferenceGuard? _assetReferences;

  final ChatSessionStorage _storage;
  late final ChatSnapshotWriter _writer = ChatSnapshotWriter(_storage.save);
  final ImageAssetStore _attachmentStore;

  ImageAssetStore get attachmentStore => _attachmentStore;

  List<ChatSession> _sessions = const [];
  String _activeId = '';
  bool _loaded = false;
  bool _loading = false;
  String? _lastError;

  DateTime? _lastUiNotifyAt;
  Timer? _pendingUiNotify;

  RecoverableHistoryStorage<ChatStoreSnapshot>? get _recovery =>
      _storage is RecoverableHistoryStorage<ChatStoreSnapshot>
      ? _storage as RecoverableHistoryStorage<ChatStoreSnapshot>
      : null;
  HistoryRecoveryState get recoveryState =>
      _recovery?.recoveryState ?? HistoryRecoveryState.healthy;
  bool get writesBlocked => _recovery?.writesBlocked ?? false;
  bool _destructive = false;
  void _assertWritable() {
    if (_destructive || _loading || writesBlocked) {
      throw const HistoryStorageException();
    }
  }

  int _activeGenerations = 0;

  /// A repository lease excludes recovery even after a completion changed the
  /// visible status. Always release locally; never rewrite an authoritative journal.
  Future<T> runGeneration<T>(
    String sessionId,
    Future<T> Function() action, {
    required String Function() itemId,
  }) async {
    try {
      _assertWritable();
    } catch (_) {
      _finishUnstarted(sessionId, itemId());
      notifyListeners();
      rethrow;
    }
    _activeGenerations++;
    try {
      return await action();
    } finally {
      _activeGenerations--;
      _finishUnstarted(sessionId, itemId());
      notifyListeners();
    }
  }

  void _finishUnstarted(String sessionId, String? itemId) {
    final index = _indexOf(sessionId);
    if (index < 0) return;
    final session = _sessions[index];
    _replace(
      index,
      session.copyWith(
        messages: [
          for (final message in session.messages)
            if ((itemId == null || message.id == itemId) && message.streaming)
              message.copyWith(
                streaming: false,
                error: true,
                errorMessage: '生成未完成；请恢复历史后重试。',
              )
            else
              message,
        ],
      ),
    );
  }

  Future<void> recoverHistory() async {
    final recovery = _recovery;
    if (recovery == null || !writesBlocked) return;
    if (_loading ||
        _activeGenerations > 0 ||
        _destructive ||
        _sessions.any((s) => s.messages.any((m) => m.streaming))) {
      throw const HistoryStorageException();
    }
    _loading = true;
    notifyListeners();
    try {
      await _writer.flush();
      final snapshot = await recovery.recover();
      _sessions = [
        for (final session in snapshot.sessions)
          session.copyWith(
            messages: [
              for (final message in session.messages)
                if (message.streaming)
                  message.copyWith(streaming: false, stopped: true)
                else
                  message,
            ],
          ),
      ];
      _activeId = snapshot.activeId;
      if (_sessions.isEmpty) {
        final session = _newSession();
        _sessions = [session];
        _activeId = session.id;
      }
      _lastError = null;
    } catch (_) {
      _lastError = '历史恢复失败，原数据已保留。';
      rethrow;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

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

  /// 立即通知；取消未触发的节流定时器。
  void _notifyUiNow() {
    _pendingUiNotify?.cancel();
    _pendingUiNotify = null;
    _lastUiNotifyAt = DateTime.now();
    notifyListeners();
  }

  /// 流式 content 合批通知；间隔内只排一次后续 flush。
  void _notifyUiThrottled() {
    final now = DateTime.now();
    final last = _lastUiNotifyAt;
    if (last == null || now.difference(last) >= kChatStreamingUiMinInterval) {
      _notifyUiNow();
      return;
    }
    if (_pendingUiNotify != null) return;
    final wait = kChatStreamingUiMinInterval - now.difference(last);
    _pendingUiNotify = Timer(wait, () {
      _pendingUiNotify = null;
      _lastUiNotifyAt = DateTime.now();
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _pendingUiNotify?.cancel();
    _pendingUiNotify = null;
    super.dispose();
  }

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
      _lastError = '历史读取失败，原数据已保留；请在设置中重试恢复。';
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

  Future<void> _persistRemoval() async {
    _destructive = true;
    try {
      await _writer.flush();
      if (_recovery != null) {
        await _recovery!.replaceHistory(
          ChatStoreSnapshot(sessions: _sessions, activeId: _activeId),
        );
      } else {
        await _persist();
      }
    } finally {
      _destructive = false;
    }
  }

  Future<void> _persist() async {
    await _writer.save(
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
    _assertWritable();
    final session = _newSession(title);
    _sessions = [session, ..._sessions];
    _activeId = session.id;
    await _persist();
    notifyListeners();
    return session;
  }

  Future<void> setActive(String id) async {
    _assertWritable();
    if (id == _activeId || !_sessions.any((s) => s.id == id)) return;
    _activeId = id;
    await _persist();
    notifyListeners();
  }

  Future<void> renameSession(String id, String title) async {
    _assertWritable();
    final index = _indexOf(id);
    if (index < 0) return;
    final t = title.trim().isEmpty ? '新对话' : title.trim();
    _replace(index, _sessions[index].copyWith(title: t, updatedAt: _now()));
    await _persist();
    notifyListeners();
  }

  Future<void> setSessionOverrides(String id, ChatOverrides overrides) async {
    _assertWritable();
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
    _assertWritable();
    _assetReferences?.retainedByOthers(this);
    final doomed = _find(id);

    _sessions = _sessions.where((s) => s.id != id).toList();
    if (_sessions.isEmpty) {
      final session = _newSession();
      _sessions = [session];
      _activeId = session.id;
    } else if (_activeId == id) {
      _activeId = _sessions.first.id;
    }
    await _persistRemoval();
    if (doomed != null) await _deleteMessageAssets(doomed.messages);
    notifyListeners();
  }

  Future<void> clearMessages(String id) async {
    _assertWritable();
    _assetReferences?.retainedByOthers(this);
    final index = _indexOf(id);
    if (index < 0) return;
    final removedAssets = _sessions[index].messages;
    _replace(
      index,
      _sessions[index].copyWith(messages: const [], updatedAt: _now()),
    );
    await _persistRemoval();
    await _deleteMessageAssets(removedAssets);
    notifyListeners();
  }

  /// 用快照整体替换（导入备份用）；空列表时自动建一条空会话。
  ///
  /// 提交成功后清理旧附件，同时使旧恢复点失效。
  Future<void> replaceAll(
    ChatStoreSnapshot snapshot, {
    bool deleteAssets = true,
  }) async {
    _assertWritable();
    _assetReferences?.retainedByOthers(this);
    final removedAssets = _sessions.expand((s) => s.messages).toList();
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
    await _persistRemoval();
    if (deleteAssets) await _deleteMessageAssets(removedAssets);
    notifyListeners();
  }

  /// Import cleanup runs only after all selected stores have committed.
  Future<void> cleanupReplacedAssets(List<ChatSession> previous) =>
      _deleteMessageAssets(previous.expand((s) => s.messages).toList());

  /// 清除全部对话会话（保留一条空会话）。幂等。
  Future<void> clearAllSessions({
    bool clearAttachmentCache = true,
    bool deleteAssets = true,
  }) async {
    if (_loading || _destructive) throw const HistoryStorageException();
    if (deleteAssets) _assetReferences?.retainedByOthers(this);
    _destructive = true;
    try {
      await _writer.flush();

      final empty = ChatStoreSnapshot(sessions: const [], activeId: '');
      if (_recovery != null) {
        await _recovery!.clearHistory(empty);
      } else {
        await _storage.save(empty);
      }
      if (deleteAssets) {
        await _deleteMessageAssets(
          _sessions.expand((s) => s.messages).toList(),
          retainCurrent: false,
        );
        if (clearAttachmentCache) {
          try {
            final retained =
                _assetReferences?.retainedByOthers(this) ?? <String>{};
            if (retained.isEmpty) {
              await _attachmentStore.clearAll();
            } else if (_attachmentStore is SelectiveAssetClear) {
              await (_attachmentStore as SelectiveAssetClear).clearExcept(
                retained,
              );
            }
          } catch (_) {}
        }
      }
      final session = _newSession();
      _sessions = [session];
      _activeId = session.id;
      await _persist();
      _loaded = true;
      _lastError = null;
      notifyListeners();
    } finally {
      _destructive = false;
    }
  }

  /// 追加消息；首条 user 截 24 字作 title（有附件无文时用「附图」）。
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
    List<ImageRef> attachments = const [],
    List<ChatToolCall> toolCalls = const [],
    List<SkillSnapshot> appliedSkills = const [],
    String? toolCallId,
    McpToolCallStatus? toolResultStatus,
  }) async {
    _assertWritable();
    final index = _indexOf(sessionId);
    if (index < 0) return null;
    final session = _sessions[index];
    final capped = sanitizeChatAttachments(attachments);
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
      attachments: capped,
      toolCalls: toolCalls,
      appliedSkills: List.unmodifiable(appliedSkills),
      toolCallId: toolCallId,
      toolResultStatus: toolResultStatus,
    );
    var title = session.title;
    if (title == '新对话' && role == ChatRole.user) {
      final slice = content.trim();
      if (slice.isNotEmpty) {
        title = slice.length <= 24 ? slice : slice.substring(0, 24);
      } else if (capped.isNotEmpty) {
        title = '附图';
      }
    }
    _replace(
      index,
      session.copyWith(
        messages: [...session.messages, item],
        title: title,
        updatedAt: _now(),
      ),
    );
    try {
      await _persist();
    } catch (_) {
      // This append never handed a task to its caller. Only settle this ID in
      // memory: save may already have published its authoritative journal.
      _finishUnstarted(sessionId, item.id);
      notifyListeners();
      rethrow;
    }
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
    List<ImageRef>? attachments,
    List<ChatToolCall>? toolCalls,
    List<SkillSnapshot>? appliedSkills,
    String? toolCallId,
    bool clearToolCallId = false,
    bool persist = true,
  }) async {
    _assertWritable();
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
      attachments: attachments == null
          ? null
          : sanitizeChatAttachments(attachments),
      toolCalls: toolCalls,
      appliedSkills: appliedSkills,
      toolCallId: toolCallId,
      clearToolCallId: clearToolCallId,
    );
    // 流式 content 合批刷 UI，且不 bump updatedAt，避免侧栏签名抖动。
    final streamingTick = streaming == true && stopped != true && error != true;
    _replace(
      index,
      session.copyWith(
        messages: msgs,
        updatedAt: streamingTick ? session.updatedAt : _now(),
      ),
    );
    if (streamingTick) {
      _notifyUiThrottled();
    } else {
      _notifyUiNow();
    }
    if (persist) await _persist();
  }

  /// 追加流式内容到指定 assistant 消息。
  Future<void> appendStreamingContent(
    String sessionId,
    String messageId,
    String delta, {
    bool persist = false,
  }) async {
    _assertWritable();
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
    _assertWritable();
    await updateMessage(
      sessionId,
      messageId,
      streaming: false,
      stopped: true,
      persist: true,
    );
  }

  /// 撤回：删最后一对 user+assistant，或指定 user 消息及其后 assistant。
  /// 返回被删 id；无操作返回 null。含附图时一并删盘。
  Future<List<String>?> recallUserMessage(
    String sessionId, {
    String? userMessageId,
  }) async {
    _assertWritable();
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
    _assetReferences?.retainedByOthers(this);
    final toDelete = msgs.sublist(idx, idx + deleteCount);
    final removedAssets = toDelete;
    final nextMsgs = List<ChatMessage>.from(msgs)
      ..removeRange(idx, idx + deleteCount);
    _replace(index, session.copyWith(messages: nextMsgs, updatedAt: _now()));
    await _persistRemoval();
    await _deleteMessageAssets(removedAssets);
    notifyListeners();
    return removedIds;
  }

  /// 将附图字节落盘为会话资产，返回 file 型 [ImageRef] 列表（最多
  /// [maxChatAttachments]）。超限 / MIME 不符的条目跳过。
  Future<List<ImageRef>> persistAttachments(
    String messageId,
    List<Uint8List> byteList, {
    List<String?>? mimes,
  }) async {
    _assertWritable();
    final out = <ImageRef>[];
    final limit = byteList.length > maxChatAttachments
        ? maxChatAttachments
        : byteList.length;
    for (var i = 0; i < limit; i++) {
      final bytes = byteList[i];
      final mime = mimes != null && i < mimes.length ? mimes[i] : null;
      if (validateChatAttachmentBytes(bytes, mime: mime) != null) {
        continue;
      }
      final path = await _attachmentStore.savePng(
        bytes,
        '$chatAttachmentIdPrefix${messageId}_$i',
      );
      out.add(ImageRef(type: ImageRefType.file, src: path));
    }
    return out;
  }

  /// 读取附图字节（file / b64）；url 返回 null。
  Future<Uint8List?> readAttachmentBytes(ImageRef ref) async {
    switch (ref.type) {
      case ImageRefType.file:
        return _attachmentStore.read(ref.src);
      case ImageRefType.b64:
        return decodeImageB64(ref.src);
      case ImageRefType.url:
        return null;
    }
  }

  Future<void> _deleteMessageAssets(
    List<ChatMessage> messages, {
    bool retainCurrent = true,
  }) async {
    final retained = retainCurrent
        ? _sessions
              .expand((s) => s.messages)
              .expand((m) => m.attachments)
              .where((i) => i.type == ImageRefType.file)
              .map((i) => assetReferenceKey(i.src))
              .toSet()
        : <String>{};
    final others = _assetReferences?.retainedByOthers(this) ?? <String>{};
    retained.addAll(others);
    for (final m in messages) {
      for (final img in m.attachments) {
        if (img.type == ImageRefType.file &&
            img.src.isNotEmpty &&
            !retained.contains(assetReferenceKey(img.src))) {
          try {
            await _attachmentStore.delete(img.src);
          } catch (_) {}
        }
      }
    }
  }
}
