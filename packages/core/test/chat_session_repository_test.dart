import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ChatSessionRepository repo;
  late MemoryChatSessionStorage storage;

  setUp(() async {
    storage = MemoryChatSessionStorage();
    repo = ChatSessionRepository(storage: storage);
    await repo.load();
  });

  test('load 空存储创建默认会话', () {
    expect(repo.sessions.length, 1);
    expect(repo.activeId, isNotEmpty);
    expect(repo.activeSession?.title, '新对话');
  });

  test('create / setActive / rename / remove', () async {
    final a = repo.activeSession!;
    final b = await repo.createSession(title: '第二');
    expect(repo.activeId, b.id);
    expect(repo.sessions.length, 2);

    await repo.setActive(a.id);
    expect(repo.activeId, a.id);

    await repo.renameSession(b.id, '改名');
    expect(repo.sessions.firstWhere((s) => s.id == b.id).title, '改名');

    await repo.removeSession(b.id);
    expect(repo.sessions.any((s) => s.id == b.id), isFalse);
    expect(repo.sessions, isNotEmpty);
  });

  test('appendMessage 首条 user 截 title', () async {
    final id = repo.activeId;
    await repo.appendMessage(
      id,
      role: ChatRole.user,
      content: '这是一段超过二十四字的用户提问内容用来截断标题测试啊',
    );
    expect(repo.activeSession!.title.length, 24);
  });

  test('流式更新与停止标记', () async {
    final sid = repo.activeId;
    final asst = await repo.appendMessage(
      sid,
      role: ChatRole.assistant,
      content: '',
      streaming: true,
    );
    await repo.appendStreamingContent(sid, asst!.id, '你好');
    await repo.appendStreamingContent(sid, asst.id, '世界');
    expect(
      repo.activeSession!.messages.last.content,
      '你好世界',
    );
    await repo.markStopped(sid, asst.id);
    final msg = repo.activeSession!.messages.last;
    expect(msg.streaming, isFalse);
    expect(msg.stopped, isTrue);
  });

  test('撤回最后一对 user+assistant', () async {
    final sid = repo.activeId;
    await repo.appendMessage(sid, role: ChatRole.user, content: 'q1');
    await repo.appendMessage(sid, role: ChatRole.assistant, content: 'a1');
    await repo.appendMessage(sid, role: ChatRole.user, content: 'q2');
    await repo.appendMessage(sid, role: ChatRole.assistant, content: 'a2');

    final removed = await repo.recallUserMessage(sid);
    expect(removed?.length, 2);
    expect(repo.activeSession!.messages.length, 2);
    expect(repo.activeSession!.messages.last.content, 'a1');
  });

  test('Memory 持久化 roundtrip', () async {
    final sid = repo.activeId;
    await repo.appendMessage(sid, role: ChatRole.user, content: '持久化');
    await repo.appendMessage(
      sid,
      role: ChatRole.assistant,
      content: 'ok',
      model: 'grok-4.5',
      latencyMs: 52000,
    );
    await repo.setSessionOverrides(
      sid,
      const ChatOverrides(systemPrompt: 'sys', temperature: 0.5),
    );

    final b = ChatSessionRepository(storage: storage);
    await b.load();
    expect(b.activeId, sid);
    expect(b.activeSession!.messages.length, 2);
    expect(b.activeSession!.messages.first.content, '持久化');
    final asst = b.activeSession!.messages.last;
    expect(asst.model, 'grok-4.5');
    expect(asst.latencyMs, 52000);
    expect(b.activeSession!.overrides.systemPrompt, 'sys');
    expect(b.activeSession!.overrides.temperature, 0.5);
  });

  test('updateMessage 写入 model/latencyMs', () async {
    final sid = repo.activeId;
    final asst = await repo.appendMessage(
      sid,
      role: ChatRole.assistant,
      content: '',
      streaming: true,
      model: 'gpt-4.1',
    );
    await repo.updateMessage(
      sid,
      asst!.id,
      streaming: false,
      latencyMs: 850,
      persist: true,
    );
    final msg = repo.activeSession!.messages.last;
    expect(msg.model, 'gpt-4.1');
    expect(msg.latencyMs, 850);
    expect(msg.streaming, isFalse);
  });

  test('GenerationRuntime begin/end token 防旧 finally', () {
    final rt = GenerationRuntime();
    var cancelled = 0;
    final t1 = rt.begin('s1', () => cancelled++);
    expect(rt.busy, isTrue);
    // 第二次 begin 会先 abort 第一次。
    final t2 = rt.begin('s2', () => cancelled++);
    expect(cancelled, 1);
    rt.end('s1', t1);
    expect(rt.sessionId, 's2');
    rt.abort('s2');
    expect(cancelled, 2);
    rt.end('s2', t2);
    expect(rt.busy, isFalse);
  });
}
