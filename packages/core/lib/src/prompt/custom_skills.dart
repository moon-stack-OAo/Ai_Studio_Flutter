import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SkillTarget {
  chat,
  image,
  video;

  String get label => switch (this) {
    chat => '对话',
    image => '生图',
    video => '生视频',
  };
}

@immutable
class CustomSkill {
  const CustomSkill({
    required this.id,
    required this.name,
    this.prompt = '',
    this.rules = '',
    this.description = '',
    this.targets = const {},
    this.enabled = true,
  });

  final String id;
  final String name;
  final String prompt;
  final String rules;
  final String description;
  final Set<SkillTarget> targets;
  final bool enabled;

  CustomSkill copyWith({
    String? id,
    String? name,
    String? prompt,
    String? rules,
    String? description,
    Set<SkillTarget>? targets,
    bool? enabled,
  }) => CustomSkill(
    id: id ?? this.id,
    name: name ?? this.name,
    prompt: prompt ?? this.prompt,
    rules: rules ?? this.rules,
    description: description ?? this.description,
    targets: Set.unmodifiable(targets ?? this.targets),
    enabled: enabled ?? this.enabled,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'prompt': prompt,
    'rules': rules,
    'description': description,
    'targets': [
      for (final t in SkillTarget.values)
        if (targets.contains(t)) t.name,
    ],
    'enabled': enabled,
  };

  factory CustomSkill.fromJson(Map<String, dynamic> json) {
    final rawTargets = json['targets'];
    if (rawTargets != null && rawTargets is! List) {
      throw const FormatException('技能适用范围必须是数组');
    }
    if (json['enabled'] != null && json['enabled'] is! bool) {
      throw const FormatException('技能启用状态必须是布尔值');
    }
    return CustomSkill(
      id: _string(json, 'id'),
      name: _string(json, 'name'),
      prompt: _string(json, 'prompt'),
      rules: _string(json, 'rules'),
      description: _string(json, 'description'),
      targets: Set.unmodifiable({
        for (final t in SkillTarget.values)
          if (rawTargets is List && rawTargets.contains(t.name)) t,
      }),
      enabled: json['enabled'] != false,
    );
  }
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return '';
  if (value is! String) throw FormatException('技能 $key 必须是字符串');
  return value;
}

@immutable
class SkillSnapshot {
  const SkillSnapshot({
    required this.id,
    required this.name,
    this.prompt = '',
    this.rules = '',
  });

  final String id;
  final String name;
  final String prompt;
  final String rules;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'prompt': prompt,
    'rules': rules,
  };

  factory SkillSnapshot.fromJson(Map<String, dynamic> json) => SkillSnapshot(
    id: _string(json, 'id'),
    name: _string(json, 'name'),
    prompt: _string(json, 'prompt'),
    rules: _string(json, 'rules'),
  );
}

/// 历史记录容错读取；损坏的快照不会使整个会话无法打开。
List<SkillSnapshot> skillSnapshotsFromJson(Object? raw) {
  final out = <SkillSnapshot>[];
  if (raw is List) {
    for (final entry in raw) {
      if (entry is! Map) continue;
      try {
        out.add(SkillSnapshot.fromJson(Map<String, dynamic>.from(entry)));
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
  }
  return List.unmodifiable(out);
}

void validateCustomSkill(CustomSkill skill) {
  if (skill.id.trim().isEmpty) throw const FormatException('技能 ID 不能为空');
  if (skill.name.trim().isEmpty) throw const FormatException('技能名称不能为空');
  if (skill.prompt.trim().isEmpty && skill.rules.trim().isEmpty) {
    throw const FormatException('提示词和规则至少填写一项');
  }
  if (skill.targets.isEmpty) throw const FormatException('请选择至少一种适用范围');
}

abstract class SkillStorage {
  Future<List<CustomSkill>> load();
  Future<void> save(List<CustomSkill> skills);
}

/// 损坏条目可恢复其余技能，并将原因交给仓库显示；不自动覆盖原始存储。
class SkillStorageFormatException extends FormatException {
  SkillStorageFormatException(super.message, this.recoveredSkills);
  final List<CustomSkill> recoveredSkills;
}

class PrefsSkillStorage implements SkillStorage {
  PrefsSkillStorage({SharedPreferences? prefs}) : _prefsOverride = prefs;
  static const prefsKey = 'core.custom_skills.v1';
  final SharedPreferences? _prefsOverride;
  Future<SharedPreferences> get _prefs async =>
      _prefsOverride ?? await SharedPreferences.getInstance();

  @override
  Future<List<CustomSkill>> load() async {
    final raw = (await _prefs).getString(prefsKey);
    if (raw == null) return const [];
    final out = <CustomSkill>[];
    var damaged = false;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) throw const FormatException('技能存储必须是数组');
      final ids = <String>{};
      for (final entry in decoded) {
        try {
          if (entry is! Map) throw const FormatException('技能必须是对象');
          final skill = CustomSkill.fromJson(Map<String, dynamic>.from(entry));
          validateCustomSkill(skill);
          if (!ids.add(skill.id)) throw const FormatException('技能 ID 重复');
          out.add(skill);
        } catch (_) {
          damaged = true;
        }
      }
    } catch (_) {
      damaged = true;
    }
    if (damaged) {
      throw SkillStorageFormatException(
        '部分技能数据损坏，已跳过无效条目',
        List.unmodifiable(out),
      );
    }
    return out;
  }

  @override
  Future<void> save(List<CustomSkill> skills) async {
    final frozen = _validated(skills);
    final ok = await (await _prefs).setString(
      prefsKey,
      jsonEncode(frozen.map((s) => s.toJson()).toList()),
    );
    if (!ok) throw StateError('技能保存失败');
  }
}

List<CustomSkill> _validated(List<CustomSkill> skills) {
  final ids = <String>{};
  return List.unmodifiable(
    skills.map((s) {
      validateCustomSkill(s);
      if (!ids.add(s.id)) throw const FormatException('技能 ID 重复');
      return s.copyWith();
    }),
  );
}

class MemorySkillStorage implements SkillStorage {
  MemorySkillStorage([List<CustomSkill> initial = const []])
    : _current = _validated(initial);
  List<CustomSkill> _current;
  List<CustomSkill> get current => _current;
  @override
  Future<List<CustomSkill>> load() async => _current;
  @override
  Future<void> save(List<CustomSkill> skills) async {
    _current = _validated(skills);
  }
}

/// 所有读写按调用顺序执行，写入成功后才发布新状态。
/// 校验/存储失败会更新 [lastError] 并抛出异常，后续操作仍可继续。
class SkillRepository extends ChangeNotifier {
  SkillRepository({required SkillStorage storage}) : _storage = storage;
  final SkillStorage _storage;
  List<CustomSkill> _skills = const [];
  List<CustomSkill> get skills => _skills;
  bool get isLoaded => _isLoaded;
  bool _isLoaded = false;
  String? get lastError => _lastError;
  String? _lastError;
  Future<void> _tail = Future.value();
  bool _disposed = false;

  Future<void> _enqueue(Future<void> Function() action) {
    if (_disposed) return Future.error(StateError('技能仓库已释放'));
    final next = _tail.then((_) async {
      try {
        await action();
      } catch (e) {
        _lastError = e.toString();
        if (!_disposed) notifyListeners();
        rethrow;
      }
    });
    _tail = next.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return next;
  }

  Future<void> load() => _enqueue(_load);
  Future<void> _load() async {
    if (_isLoaded) return;
    try {
      _skills = _validated(await _storage.load());
      _lastError = null;
    } on SkillStorageFormatException catch (e) {
      _skills = _validated(e.recoveredSkills);
      _lastError = e.message;
    }
    _isLoaded = true;
    if (!_disposed) notifyListeners();
  }

  Future<void> _change(List<CustomSkill> Function() transform) =>
      _enqueue(() async {
        await _load();
        final next = _validated(transform());
        await _storage.save(next);
        _skills = next;
        _lastError = null;
        if (!_disposed) notifyListeners();
      });

  Future<void> saveSkill(CustomSkill skill) {
    final frozen = skill.copyWith();
    return _change(() {
      final next = [..._skills];
      final index = next.indexWhere((s) => s.id == frozen.id);
      if (index < 0) {
        next.add(frozen);
      } else {
        next[index] = frozen;
      }
      return next;
    });
  }

  Future<void> deleteSkill(String id) =>
      _change(() => _skills.where((s) => s.id != id).toList());

  Future<void> setEnabled(String id, bool enabled) => _change(
    () => [
      for (final s in _skills) s.id == id ? s.copyWith(enabled: enabled) : s,
    ],
  );

  Future<void> moveSkill(String id, int offset) => _change(() {
    final next = [..._skills];
    final index = next.indexWhere((s) => s.id == id);
    if (index < 0) return next;
    final destination = (index + offset).clamp(0, next.length - 1);
    next.insert(destination, next.removeAt(index));
    return next;
  });
  Future<void> replaceAll(List<CustomSkill> skills) {
    final frozen = [for (final s in skills) s.copyWith()];
    return _change(() => frozen);
  }

  /// 本地原位更新；新 ID 按传入顺序追加。同批重复 ID 由校验拒绝。
  Future<void> merge(List<CustomSkill> skills) {
    final frozen = [for (final s in skills) s.copyWith()];
    return _change(() {
      final incoming = _validated(frozen);
      final byId = {for (final s in incoming) s.id: s};
      final localIds = _skills.map((s) => s.id).toSet();
      return [
        for (final s in _skills) byId[s.id] ?? s,
        for (final s in incoming)
          if (!localIds.contains(s.id)) s,
      ];
    });
  }

  Future<void> clear() => replaceAll(const []);

  List<CustomSkill> activeFor(SkillTarget target) => List.unmodifiable(
    _skills.where((s) => s.enabled && s.targets.contains(target)),
  );

  List<SkillSnapshot> snapshotFor(SkillTarget target) => List.unmodifiable(
    activeFor(target).map(
      (s) => SkillSnapshot(
        id: s.id,
        name: s.name,
        prompt: s.prompt,
        rules: s.rules,
      ),
    ),
  );

  /// 使用固定字段顺序的 JSON，避免 hashCode 跨进程不稳定或哈希碰撞。
  String fingerprintFor(SkillTarget target) =>
      jsonEncode(snapshotFor(target).map((s) => s.toJson()).toList());

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

String _skillSections(List<SkillSnapshot> skills) => skills
    .map(
      (s) => [
        '【技能：${s.name}】',
        if (s.prompt.trim().isNotEmpty) '提示词：\n${s.prompt}',
        if (s.rules.trim().isNotEmpty) '规则：\n${s.rules}',
      ].join('\n'),
    )
    .join('\n\n');

String composeSkillPrompt({
  required String prompt,
  required List<SkillSnapshot> skills,
}) => skills.isEmpty ? prompt : '${_skillSections(skills)}\n\n【用户需求】\n$prompt';

String composeChatSystemPrompt(String base, List<SkillSnapshot> skills) =>
    skills.isEmpty
    ? base
    : [if (base.isNotEmpty) base, _skillSections(skills)].join('\n\n');
