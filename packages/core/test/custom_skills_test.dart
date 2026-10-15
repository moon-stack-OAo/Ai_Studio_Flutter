import 'dart:async';
import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

CustomSkill skill(
  String id, {
  Set<SkillTarget> targets = const {SkillTarget.image},
}) => CustomSkill(
  id: id,
  name: id,
  prompt: 'prompt-$id',
  rules: 'rules-$id',
  targets: targets,
);

class ControlledStorage extends MemorySkillStorage {
  bool failLoad = false;
  bool failSave = false;
  int failuresRemaining = 0;
  Completer<void>? gate;
  final writes = <List<String>>[];

  @override
  Future<List<CustomSkill>> load() async {
    if (failLoad) throw StateError('读取失败');
    return super.load();
  }

  @override
  Future<void> save(List<CustomSkill> skills) async {
    writes.add(skills.map((s) => s.id).toList());
    await gate?.future;
    if (failSave) throw StateError('保存失败');
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw StateError('本次保存失败');
    }
    await super.save(skills);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('JSON、label、无技能原文与按序分区', () {
    expect(SkillTarget.values.map((t) => t.label), ['对话', '生图', '生视频']);
    final value = skill('a', targets: {SkillTarget.video, SkillTarget.image});
    expect(CustomSkill.fromJson(value.toJson()).toJson(), value.toJson());
    const snapshot = SkillSnapshot(
      id: 'a',
      name: 'A',
      prompt: '前缀',
      rules: '限制',
    );
    expect(
      SkillSnapshot.fromJson(snapshot.toJson()).toJson(),
      snapshot.toJson(),
    );
    expect(composeSkillPrompt(prompt: ' 原文\n', skills: []), ' 原文\n');
    expect(composeChatSystemPrompt(' 原文\n', []), ' 原文\n');
    expect(
      composeSkillPrompt(prompt: '猫', skills: [snapshot]),
      '【技能：A】\n提示词：\n前缀\n规则：\n限制\n\n【用户需求】\n猫',
    );
    expect(
      composeChatSystemPrompt('system', [snapshot]),
      startsWith('system\n\n【技能：A】'),
    );
  });

  test('校验失败不写存储，失败显示 lastError，下一次操作可恢复', () async {
    final storage = ControlledStorage();
    final repo = SkillRepository(storage: storage);
    for (final invalid in [
      skill('a').copyWith(name: ' '),
      skill('a').copyWith(prompt: '', rules: ' '),
      skill('a').copyWith(targets: {}),
      skill('a').copyWith(id: ''),
    ]) {
      await expectLater(repo.saveSkill(invalid), throwsFormatException);
      expect(repo.lastError, isNotNull);
      expect(repo.skills, isEmpty);
    }
    expect(storage.writes, isEmpty);
    await expectLater(
      repo.replaceAll([skill('a'), skill('a')]),
      throwsFormatException,
    );
    await repo.saveSkill(skill('a'));
    expect(repo.lastError, isNull);
    storage.failSave = true;
    await expectLater(repo.saveSkill(skill('b')), throwsStateError);
    expect(repo.skills.map((s) => s.id), ['a']);
    expect(storage.current.map((s) => s.id), ['a']);
    expect(repo.lastError, contains('保存失败'));
    storage.failSave = false;
    await repo.saveSkill(skill('b'));
    expect(repo.skills.map((s) => s.id), ['a', 'b']);
  });

  test('读取失败不被当成空存储覆盖，可重试', () async {
    final storage = ControlledStorage()..failLoad = true;
    final repo = SkillRepository(storage: storage);
    await expectLater(repo.load(), throwsStateError);
    expect(repo.isLoaded, isFalse);
    await expectLater(repo.saveSkill(skill('a')), throwsStateError);
    expect(storage.writes, isEmpty);
    storage.failLoad = false;
    await repo.saveSkill(skill('a'));
    expect(repo.isLoaded, isTrue);
    expect(repo.lastError, isNull);
  });

  test('并发保存串行，无丢失；读取与清空参与同一队列', () async {
    final storage = ControlledStorage()..gate = Completer<void>();
    final repo = SkillRepository(storage: storage);
    final first = repo.saveSkill(skill('a'));
    final second = repo.saveSkill(skill('b'));
    final load = repo.load();
    await Future<void>.delayed(Duration.zero);
    expect(storage.writes, [
      ['a'],
    ]);
    expect(repo.skills, isEmpty);
    storage.gate!.complete();
    await Future.wait([first, second, load]);
    expect(storage.writes, [
      ['a'],
      ['a', 'b'],
    ]);
    expect(repo.skills.map((s) => s.id), ['a', 'b']);
    await Future.wait([repo.clear(), repo.saveSkill(skill('c'))]);
    expect(storage.current.map((s) => s.id), ['c']);
  });

  test('列表和 targets 隔离调用方修改；快照保持不可变', () async {
    final targets = {SkillTarget.image};
    final input = [skill('a', targets: targets)];
    final repo = SkillRepository(storage: MemorySkillStorage());
    final pending = repo.replaceAll(input);
    targets.clear();
    input.clear();
    await pending;
    final snapshot = repo.snapshotFor(SkillTarget.image);
    expect(snapshot.single.id, 'a');
    expect(() => repo.skills.clear(), throwsUnsupportedError);
    expect(() => repo.skills.single.targets.clear(), throwsUnsupportedError);
    expect(() => snapshot.clear(), throwsUnsupportedError);
    await repo.saveSkill(skill('a').copyWith(prompt: '新内容'));
    expect(snapshot.single.prompt, 'prompt-a');
  });

  test('并发队列首笔失败不阻断后续保存，后续操作以已提交状态为准', () async {
    final storage = ControlledStorage()..failuresRemaining = 1;
    final repo = SkillRepository(storage: storage);
    final failed = expectLater(repo.saveSkill(skill('a')), throwsStateError);
    final succeeded = repo.saveSkill(skill('b'));
    await Future.wait([failed, succeeded]);
    expect(storage.writes, [
      ['a'],
      ['b'],
    ]);
    expect(repo.skills.map((s) => s.id), ['b']);
    expect(storage.current.map((s) => s.id), ['b']);
    expect(repo.lastError, isNull);
  });

  test('原位更新、过滤、移动、合并及 fingerprint 只依赖有效内容和顺序', () async {
    final repo = SkillRepository(storage: MemorySkillStorage());
    await repo.replaceAll([
      skill('a'),
      skill('chat', targets: {SkillTarget.chat}),
      skill('b'),
      skill('disabled').copyWith(enabled: false),
    ]);
    final initial = repo.fingerprintFor(SkillTarget.image);
    await repo.saveSkill(skill('a').copyWith(description: '说明变化'));
    await repo.saveSkill(
      skill('chat', targets: {SkillTarget.chat}).copyWith(prompt: '其他类型变化'),
    );
    expect(repo.fingerprintFor(SkillTarget.image), initial);
    await repo.moveSkill('b', -2);
    expect(repo.activeFor(SkillTarget.image).map((s) => s.id), ['b', 'a']);
    expect(repo.fingerprintFor(SkillTarget.image), isNot(initial));
    await repo.moveSkill('b', 999);
    expect(repo.activeFor(SkillTarget.image).map((s) => s.id), ['a', 'b']);
    expect(repo.fingerprintFor(SkillTarget.image), initial);
    await repo.merge([
      skill('b').copyWith(name: '更新B'),
      skill('new2'),
      skill('new1'),
    ]);
    expect(repo.skills.map((s) => s.id), [
      'a',
      'chat',
      'disabled',
      'b',
      'new2',
      'new1',
    ]);
    expect(repo.skills[3].name, '更新B');
    await repo.setEnabled('a', false);
    expect(repo.activeFor(SkillTarget.image).map((s) => s.id), [
      'b',
      'new2',
      'new1',
    ]);
    await repo.deleteSkill('b');
    expect(repo.skills.any((s) => s.id == 'b'), isFalse);
    final reloaded = SkillRepository(storage: MemorySkillStorage(repo.skills));
    await reloaded.load();
    expect(
      reloaded.fingerprintFor(SkillTarget.image),
      repo.fingerprintFor(SkillTarget.image),
    );
  });

  test('Prefs roundtrip 与损坏条目恢复，保留原始数据并提示', () async {
    final raw = jsonEncode([
      skill('a').toJson(),
      {'id': 'broken'},
      skill('a').toJson(),
      42,
    ]);
    SharedPreferences.setMockInitialValues({PrefsSkillStorage.prefsKey: raw});
    final prefs = await SharedPreferences.getInstance();
    final repo = SkillRepository(storage: PrefsSkillStorage(prefs: prefs));
    await repo.load();
    expect(repo.isLoaded, isTrue);
    expect(repo.skills.map((s) => s.id), ['a']);
    expect(repo.lastError, contains('损坏'));
    expect(prefs.getString(PrefsSkillStorage.prefsKey), raw);
    await repo.saveSkill(skill('b'));
    expect(repo.lastError, isNull);
    final reload = SkillRepository(storage: PrefsSkillStorage(prefs: prefs));
    await reload.load();
    expect(reload.skills.map((s) => s.id), ['a', 'b']);
    await prefs.setString(PrefsSkillStorage.prefsKey, '{invalid');
    final corrupted = SkillRepository(storage: PrefsSkillStorage(prefs: prefs));
    await corrupted.load();
    expect(corrupted.skills, isEmpty);
    expect(corrupted.lastError, isNotNull);
  });

  test('历史 JSON 缺省字段兼容，copyWith 与往返保留真实请求和快照', () {
    final message = ChatMessage.fromJson({
      'id': 'm',
      'role': 'user',
      'content': '猫',
    });
    final image = ImageItem.fromJson({'id': 'i', 'prompt': '猫'});
    final video = VideoItem.fromJson({'id': 'v', 'prompt': '猫'});
    expect(message.appliedSkills, isEmpty);
    expect(image.appliedSkills, isEmpty);
    expect(video.appliedSkills, isEmpty);
    expect(image.finalPrompt, '猫');
    expect(video.finalPrompt, '猫');
    const snapshots = [SkillSnapshot(id: 'a', name: 'A', rules: '限制')];
    final updatedMessage = message
        .copyWith(appliedSkills: snapshots)
        .copyWith(content: '新正文');
    final updatedImage = image
        .copyWith(finalPrompt: '实际请求', appliedSkills: snapshots)
        .copyWith(status: ImageItemStatus.error);
    final updatedVideo = video
        .copyWith(finalPrompt: '实际请求', appliedSkills: snapshots)
        .copyWith(progress: 50);
    expect(
      ChatMessage.fromJson(updatedMessage.toJson()).appliedSkills.single.rules,
      '限制',
    );
    expect(ImageItem.fromJson(updatedImage.toJson()).finalPrompt, '实际请求');
    expect(
      ImageItem.fromJson(updatedImage.toJson()).appliedSkills.single.rules,
      '限制',
    );
    expect(VideoItem.fromJson(updatedVideo.toJson()).finalPrompt, '实际请求');
    expect(
      VideoItem.fromJson(updatedVideo.toJson()).appliedSkills.single.rules,
      '限制',
    );
    expect(
      skillSnapshotsFromJson([
        42,
        {'name': 42},
        snapshots.single.toJson(),
      ]),
      hasLength(1),
    );
  });
}
