import 'dart:async';
import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('ChatDefaults JSON roundtrip', () {
    const original = ChatDefaults(
      temperature: 1.2,
      systemPrompt: '你是助手',
      maxTokens: 2048,
      apiTimeoutMs: 120000,
      contextTrimEnabled: false,
      contextMaxTurns: 8,
      contextMaxCharsEnabled: true,
      contextMaxChars: 16000,
    );
    final restored = ChatDefaults.fromJson(original.toJson());
    expect(restored, original);
  });

  test('sanitized clamps out-of-range', () {
    final bad = const ChatDefaults(
      temperature: 9,
      maxTokens: -3,
      apiTimeoutMs: 10,
      contextMaxTurns: 0,
      contextMaxChars: 0,
    ).sanitized();
    expect(bad.temperature, 2.0);
    expect(bad.maxTokens, 0);
    expect(bad.apiTimeoutMs, 1000);
    expect(bad.contextMaxTurns, 1);
    expect(bad.contextMaxChars, 1);
  });

  test('MemoryChatDefaultsStorage roundtrip via repository', () async {
    final storage = MemoryChatDefaultsStorage();
    final repo = ChatDefaultsRepository(storage: storage);
    await repo.load();
    expect(repo.defaults.temperature, defaultChatTemperature);

    await repo.update(
      temperature: 0.3,
      systemPrompt: 'sys',
      maxTokens: 512,
      apiTimeoutMs: 90000,
      contextTrimEnabled: true,
      contextMaxTurns: 12,
      contextMaxCharsEnabled: true,
      contextMaxChars: 8000,
    );
    expect(repo.defaults.temperature, 0.3);
    expect(repo.defaults.systemPrompt, 'sys');
    expect(storage.current.maxTokens, 512);

    final other = ChatDefaultsRepository(storage: storage);
    await other.load();
    expect(other.defaults, repo.defaults);

    await other.resetToRecommended();
    expect(other.defaults, ChatDefaults.recommended);
  });

  test('PrefsChatDefaultsStorage roundtrip with injected prefs', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = PrefsChatDefaultsStorage(prefs: prefs);
    await storage.save(
      const ChatDefaults(
        temperature: 0.55,
        systemPrompt: 'prefs',
        maxTokens: 100,
      ),
    );
    final loaded = await storage.load();
    expect(loaded.temperature, 0.55);
    expect(loaded.systemPrompt, 'prefs');
    expect(loaded.maxTokens, 100);
    expect(prefs.getString(PrefsChatDefaultsStorage.prefsKey), isNotEmpty);
  });

  test('保存成功前不发布，成功通知中已清除错误', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final storage = _ControlledStorage()
      ..onSave = (_) {
        started.complete();
        return release.future;
      };
    final repo = ChatDefaultsRepository(storage: storage);
    addTearDown(repo.dispose);
    final published = <ChatDefaults>[];
    repo.addListener(() {
      expect(repo.lastError, isNull);
      published.add(repo.defaults);
    });
    const next = ChatDefaults(temperature: 0.3);
    final saving = repo.save(next);
    await started.future;
    expect(repo.defaults, ChatDefaults.recommended);
    expect(published, isEmpty);
    release.complete();
    await saving;
    expect(repo.defaults, next);
    expect(storage.current, next);
    expect(published, [next]);
  });

  test('保存失败保留生效配置，重试成功后才发布并清除错误', () async {
    const initial = ChatDefaults(systemPrompt: '原配置');
    const draft = ChatDefaults(systemPrompt: '待重试的草稿');
    final failure = StateError('磁盘写入失败');
    final storage = _ControlledStorage(initial)
      ..onSave = (_) async => throw failure;
    final repo = ChatDefaultsRepository(storage: storage);
    addTearDown(repo.dispose);
    await repo.load();
    final published = <ChatDefaults>[];
    final errors = <String?>[];
    repo.addListener(() {
      published.add(repo.defaults);
      errors.add(repo.lastError);
    });
    await expectLater(repo.save(draft), throwsA(same(failure)));
    expect(repo.defaults, initial);
    expect(storage.current, initial);
    expect(published, [initial]);
    expect(errors, [failure.toString()]);

    storage.onSave = null;
    await repo.save(draft);
    expect(repo.defaults, draft);
    expect(storage.current, draft);
    expect(published, [initial, draft]);
    expect(errors, [failure.toString(), null]);
  });

  test('并发保存按调用顺序写入并发布', () async {
    final firstStarted = Completer<void>();
    final firstRelease = Completer<void>();
    final secondStarted = Completer<void>();
    final secondRelease = Completer<void>();
    const first = ChatDefaults(systemPrompt: 'first');
    const second = ChatDefaults(systemPrompt: 'second');
    final storage = _ControlledStorage()
      ..onSave = (next) {
        if (next == first) {
          firstStarted.complete();
          return firstRelease.future;
        }
        secondStarted.complete();
        return secondRelease.future;
      };
    final repo = ChatDefaultsRepository(storage: storage);
    addTearDown(repo.dispose);
    final published = <ChatDefaults>[];
    repo.addListener(() => published.add(repo.defaults));
    final firstSave = repo.save(first);
    final secondSave = repo.save(second);
    await firstStarted.future;
    expect(storage.writes, [first]);
    expect(published, isEmpty);
    firstRelease.complete();
    await firstSave;
    await secondStarted.future;
    expect(repo.defaults, first);
    expect(storage.current, first);
    expect(storage.writes, [first, second]);
    secondRelease.complete();
    await secondSave;
    expect(repo.defaults, second);
    expect(storage.current, second);
    expect(published, [first, second]);
  });

  test('前次保存失败不阻断已经排队的后续保存', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final failure = StateError('第一次失败');
    const first = ChatDefaults(systemPrompt: 'first');
    const second = ChatDefaults(systemPrompt: 'second');
    final storage = _ControlledStorage()
      ..onSave = (next) {
        if (next == first) {
          started.complete();
          return release.future;
        }
        return Future<void>.value();
      };
    final repo = ChatDefaultsRepository(storage: storage);
    addTearDown(repo.dispose);
    final firstCheck = expectLater(repo.save(first), throwsA(same(failure)));
    final secondSave = repo.save(second);
    await started.future;
    release.completeError(failure);
    await firstCheck;
    await secondSave;
    expect(storage.writes, [first, second]);
    expect(repo.defaults, second);
    expect(storage.current, second);
    expect(repo.lastError, isNull);
  });

  test('后续保存失败不回滚已成功的并发保存', () async {
    const first = ChatDefaults(systemPrompt: 'first');
    const second = ChatDefaults(systemPrompt: 'second');
    final failure = StateError('第二次失败');
    final storage = _ControlledStorage()
      ..onSave = (next) async {
        if (next == second) throw failure;
      };
    final repo = ChatDefaultsRepository(storage: storage);
    addTearDown(repo.dispose);
    final firstSave = repo.save(first);
    final secondCheck = expectLater(repo.save(second), throwsA(same(failure)));
    await firstSave;
    await secondCheck;
    expect(repo.defaults, first);
    expect(storage.current, first);
    expect(repo.lastError, failure.toString());
  });

  test('并发局部更新基于前一次成功配置合并', () async {
    final repo = ChatDefaultsRepository(storage: _ControlledStorage());
    addTearDown(repo.dispose);
    await Future.wait([
      repo.update(temperature: 0.2),
      repo.update(systemPrompt: '保留温度更新'),
    ]);
    expect(repo.defaults.temperature, 0.2);
    expect(repo.defaults.systemPrompt, '保留温度更新');
  });

  test('进行中的 load 不会在后续 save 之后覆盖新配置', () async {
    const initial = ChatDefaults(systemPrompt: '旧存储');
    const next = ChatDefaults(systemPrompt: '新配置');
    final started = Completer<void>();
    final release = Completer<ChatDefaults>();
    final storage = _ControlledStorage(initial)
      ..onLoad = () {
        started.complete();
        return release.future;
      };
    final repo = ChatDefaultsRepository(storage: storage);
    addTearDown(repo.dispose);
    final loading = repo.load();
    final saving = repo.save(next);
    await started.future;
    expect(repo.isLoading, isTrue);
    expect(storage.writes, isEmpty);
    release.complete(initial);
    await loading;
    await saving;
    expect(repo.isLoaded, isTrue);
    expect(repo.isLoading, isFalse);
    expect(repo.defaults, next);
    expect(storage.current, next);
  });

  test('save 后调用 load 会等待写入完成再读取', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    var reads = 0;
    final storage = _ControlledStorage();
    storage.onLoad = () async {
      reads++;
      return storage.current;
    };
    storage.onSave = (_) {
      started.complete();
      return release.future;
    };
    final repo = ChatDefaultsRepository(storage: storage);
    addTearDown(repo.dispose);
    const next = ChatDefaults(systemPrompt: '等待持久化');
    final saving = repo.save(next);
    final loading = repo.load();
    await started.future;
    expect(reads, 0);
    release.complete();
    await saving;
    await loading;
    expect(reads, 1);
    expect(repo.defaults, next);
  });

  test('重复 load 仍被忽略，读取失败仍回退推荐配置并允许后续保存', () async {
    final started = Completer<void>();
    final release = Completer<ChatDefaults>();
    final failure = StateError('读取失败');
    var reads = 0;
    final storage = _ControlledStorage()
      ..onLoad = () {
        reads++;
        started.complete();
        return release.future;
      };
    final repo = ChatDefaultsRepository(storage: storage);
    addTearDown(repo.dispose);
    final loading = repo.load();
    await started.future;
    await repo.load();
    expect(reads, 1);
    release.completeError(failure);
    await loading;
    expect(repo.defaults, ChatDefaults.recommended);
    expect(repo.isLoaded, isTrue);
    expect(repo.isLoading, isFalse);
    expect(repo.lastError, failure.toString());
    await repo.save(const ChatDefaults(temperature: 0.1));
    expect(repo.defaults.temperature, 0.1);
    expect(repo.lastError, isNull);
  });

  test('失败保存之后排队的 load 成功时清除前次错误', () async {
    const initial = ChatDefaults(systemPrompt: '磁盘配置');
    final failure = StateError('保存失败');
    final storage = _ControlledStorage(initial)
      ..onSave = (_) async => throw failure;
    final repo = ChatDefaultsRepository(storage: storage);
    addTearDown(repo.dispose);
    final savingCheck = expectLater(
      repo.save(const ChatDefaults(systemPrompt: '失败草稿')),
      throwsA(same(failure)),
    );
    final loading = repo.load();
    await savingCheck;
    await loading;
    expect(repo.defaults, initial);
    expect(repo.lastError, isNull);
    expect(repo.isLoaded, isTrue);
    expect(repo.isLoading, isFalse);
  });

  for (final throwsOnSave in [false, true]) {
    test(
      'prefs 写入${throwsOnSave ? '抛出异常' : '返回 false'}时不发布，重新加载恢复磁盘配置',
      () async {
        const initial = ChatDefaults(systemPrompt: '磁盘配置');
        final prefs = _FailingPrefs(initial, throwsOnSave: throwsOnSave);
        final storage = PrefsChatDefaultsStorage(prefs: prefs);
        final repo = ChatDefaultsRepository(storage: storage);
        addTearDown(repo.dispose);
        await repo.load();
        await expectLater(
          repo.save(const ChatDefaults(systemPrompt: '失败草稿')),
          throwsA(isA<StateError>()),
        );
        expect(repo.defaults, initial);
        expect(repo.lastError, contains('保存'));
        expect(await storage.load(), initial);
        await repo.load();
        expect(repo.defaults, initial);
      },
    );
  }

  test('prefs 保存失败后 reload 也失败时，下次 load 必须重读而不能返回草稿缓存', () async {
    const initial = ChatDefaults(systemPrompt: '磁盘配置');
    final prefs = _FailingPrefs(initial)..failReload = true;
    final storage = PrefsChatDefaultsStorage(prefs: prefs);
    await expectLater(
      storage.save(const ChatDefaults(systemPrompt: '失败草稿')),
      throwsA(
        isA<StateError>().having((e) => e.message, 'message', contains('保存')),
      ),
    );
    await expectLater(storage.load(), throwsA(isA<StateError>()));
    prefs.failReload = false;
    expect(await storage.load(), initial);
  });
}

class _ControlledStorage implements ChatDefaultsStorage {
  _ControlledStorage([this.current = ChatDefaults.recommended]);

  ChatDefaults current;
  final writes = <ChatDefaults>[];
  Future<ChatDefaults> Function()? onLoad;
  Future<void> Function(ChatDefaults)? onSave;

  @override
  Future<ChatDefaults> load() async =>
      onLoad == null ? current : await onLoad!();

  @override
  Future<void> save(ChatDefaults defaults) async {
    writes.add(defaults);
    await onSave?.call(defaults);
    current = defaults;
  }
}

// 模拟插件先修改缓存、随后返回失败或抛错的实际顺序。
class _FailingPrefs extends Fake implements SharedPreferences {
  _FailingPrefs(ChatDefaults initial, {this.throwsOnSave = false})
    : _persisted = jsonEncode(initial.toJson()),
      _cached = jsonEncode(initial.toJson());

  final bool throwsOnSave;
  final String _persisted;
  String _cached;
  bool failReload = false;

  @override
  String? getString(String key) => _cached;

  @override
  Future<bool> setString(String key, String value) async {
    _cached = value;
    if (throwsOnSave) throw StateError('保存失败');
    return false;
  }

  @override
  Future<void> reload() async {
    if (failReload) throw StateError('重新读取失败');
    _cached = _persisted;
  }
}
