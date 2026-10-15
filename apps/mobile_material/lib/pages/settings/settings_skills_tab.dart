import 'dart:async';

import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> openSkillManagement(
  BuildContext context,
  SkillRepository repository,
) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('自定义技能')),
        body: SettingsSkillsTab(repository: repository),
      ),
    ),
  );
}

class SettingsSkillsTab extends StatefulWidget {
  const SettingsSkillsTab({super.key, required this.repository});

  final SkillRepository repository;

  @override
  State<SettingsSkillsTab> createState() => _SettingsSkillsTabState();
}

class _SettingsSkillsTabState extends State<SettingsSkillsTab> {
  SkillTarget? _filter;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (!widget.repository.isLoaded) {
      unawaited(widget.repository.load().catchError((Object _) {}));
    }
  }

  Future<void> _mutate(Future<dynamic> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    String? error;
    try {
      await action();
      error = widget.repository.lastError;
    } catch (e) {
      error = sanitizeErrorText(e.toString(), '技能保存失败');
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _edit([CustomSkill? skill]) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            SkillEditorPage(repository: widget.repository, skill: skill),
      ),
    );
  }

  Future<void> _delete(CustomSkill skill) async {
    final ok = await showMaterialConfirmDialog(
      context: context,
      title: '删除技能',
      message: '确定删除「${skill.name}」？历史记录中的技能快照会保留。',
      confirmLabel: '删除',
      isDestructive: true,
    );
    if (ok && mounted) {
      await _mutate(() => widget.repository.deleteSkill(skill.id));
    }
  }

  void _reorder(List<CustomSkill> skills, int oldIndex, int newIndex) {
    if (_busy || oldIndex < 0 || oldIndex >= skills.length) return;
    if (newIndex > oldIndex) newIndex--;
    if (newIndex < 0 || newIndex >= skills.length || oldIndex == newIndex) {
      return;
    }
    final all = widget.repository.skills;
    final source = skills[oldIndex];
    final sourceGlobal = all.indexWhere((s) => s.id == source.id);
    final targetGlobal = all.indexWhere((s) => s.id == skills[newIndex].id);
    if (sourceGlobal < 0 || targetGlobal < 0 || sourceGlobal == targetGlobal) {
      return;
    }
    unawaited(
      _mutate(
        () =>
            widget.repository.moveSkill(source.id, targetGlobal - sourceGlobal),
      ),
    );
  }

  void _skillAction(_SkillAction action, CustomSkill skill) {
    if (_busy) return;
    switch (action) {
      case _SkillAction.copy:
        unawaited(
          _mutate(
            () => widget.repository.saveSkill(
              skill.copyWith(
                id: 'skill_${DateTime.now().microsecondsSinceEpoch}',
                name: '${skill.name} 副本',
                enabled: false,
              ),
            ),
          ),
        );
      case _SkillAction.edit:
        unawaited(_edit(skill));
      case _SkillAction.delete:
        unawaited(_delete(skill));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.repository,
      builder: (context, _) {
        final all = widget.repository.skills;
        final skills = all
            .where((s) => _filter == null || s.targets.contains(_filter))
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  const Expanded(child: Text('全局自动生效，按列表顺序应用')),
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _edit(),
                    icon: const Icon(Icons.add),
                    label: const Text('新建技能'),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('全部'),
                    selected: _filter == null,
                    onSelected: (_) => setState(() => _filter = null),
                  ),
                  for (final target in SkillTarget.values)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: ChoiceChip(
                        label: Text(target.label),
                        selected: _filter == target,
                        onSelected: (_) => setState(() => _filter = target),
                      ),
                    ),
                ],
              ),
            ),
            if (widget.repository.lastError != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  widget.repository.lastError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (!widget.repository.isLoaded &&
                widget.repository.lastError != null)
              TextButton(
                onPressed: _busy ? null : () => _mutate(widget.repository.load),
                child: const Text('重试加载'),
              ),
            if (_busy) const LinearProgressIndicator(),
            Expanded(
              child: skills.isEmpty
                  ? const Center(child: Text('暂无技能，点击「新建技能」开始'))
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                      buildDefaultDragHandles: false,
                      // 保留原始插入索引，统一处理拖动、读屏和键盘排序。
                      // ignore: deprecated_member_use
                      onReorder: (oldIndex, newIndex) =>
                          _reorder(skills, oldIndex, newIndex),
                      proxyDecorator: (child, index, animation) => Material(
                        color: Theme.of(context).colorScheme.surface,
                        elevation: 6,
                        borderRadius: BorderRadius.circular(12),
                        child: child,
                      ),
                      itemCount: skills.length,
                      itemBuilder: (context, index) {
                        final skill = skills[index];
                        return Card(
                          key: ValueKey(skill.id),
                          child: Row(
                            children: [
                              _SkillDragHandle(
                                index: index,
                                enabled: !_busy,
                                onMoveUp: index == 0
                                    ? null
                                    : () => _reorder(skills, index, index - 1),
                                onMoveDown: index == skills.length - 1
                                    ? null
                                    : () => _reorder(skills, index, index + 2),
                              ),
                              Expanded(
                                child: InkWell(
                                  onTap: _busy ? null : () => _edit(skill),
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      minHeight: 48,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 12,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            skill.name,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleMedium,
                                          ),
                                          Text(
                                            skill.targets.isEmpty
                                                ? '未选择适用类型'
                                                : skill.targets
                                                      .map((t) => t.label)
                                                      .join(' · '),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                          if (skill.description.isNotEmpty)
                                            Text(
                                              skill.description,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Semantics(
                                label: '启用技能：${skill.name}',
                                child: SizedBox(
                                  width: 60,
                                  height: 48,
                                  child: Switch(
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.padded,
                                    value: skill.enabled,
                                    onChanged: _busy
                                        ? null
                                        : (v) => _mutate(
                                            () => widget.repository.setEnabled(
                                              skill.id,
                                              v,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 48,
                                height: 48,
                                child: PopupMenuButton<_SkillAction>(
                                  tooltip: '技能操作',
                                  enabled: !_busy,
                                  icon: const Icon(Icons.more_vert),
                                  onSelected: (action) =>
                                      _skillAction(action, skill),
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: _SkillAction.copy,
                                      child: Text('复制（默认停用）'),
                                    ),
                                    PopupMenuItem(
                                      value: _SkillAction.edit,
                                      child: Text('编辑'),
                                    ),
                                    PopupMenuItem(
                                      value: _SkillAction.delete,
                                      child: Text('删除'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

enum _SkillAction { copy, edit, delete }

class _SkillDragHandle extends StatelessWidget {
  const _SkillDragHandle({
    required this.index,
    required this.enabled,
    this.onMoveUp,
    this.onMoveDown,
  });

  final int index;
  final bool enabled;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        if (enabled && onMoveUp != null)
          const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true):
              onMoveUp!,
        if (enabled && onMoveDown != null)
          const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true):
              onMoveDown!,
      },
      child: Focus(
        child: Builder(
          builder: (context) => Semantics(
            hint: '拖动手柄排序；键盘 Alt 加上下方向键排序',
            child: Tooltip(
              message: '拖动排序',
              child: ReorderableDragStartListener(
                index: index,
                enabled: enabled,
                child: Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Focus.of(context).hasFocus
                        ? Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 2,
                          )
                        : null,
                  ),
                  child: Icon(
                    Icons.drag_handle,
                    color: enabled
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : Theme.of(context).disabledColor,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SkillEditorPage extends StatefulWidget {
  const SkillEditorPage({super.key, required this.repository, this.skill});

  final SkillRepository repository;
  final CustomSkill? skill;

  @override
  State<SkillEditorPage> createState() => _SkillEditorPageState();
}

enum _LeaveAction { save, discard, keepEditing }

class _SkillEditorPageState extends State<SkillEditorPage> {
  late final CustomSkill _original;
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _prompt;
  late final TextEditingController _rules;
  late Set<SkillTarget> _targets;
  bool _saving = false;
  bool _leaving = false;
  bool _allowPop = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _original =
        widget.skill ??
        CustomSkill(
          id: 'skill_${DateTime.now().microsecondsSinceEpoch}',
          name: '',
        );
    _name = TextEditingController(text: _original.name);
    _description = TextEditingController(text: _original.description);
    _prompt = TextEditingController(text: _original.prompt);
    _rules = TextEditingController(text: _original.rules);
    _targets = {..._original.targets};
    for (final c in [_name, _description, _prompt, _rules]) {
      c.addListener(_edited);
    }
  }

  void _edited() {
    if (mounted) setState(() => _error = null);
  }

  bool get _dirty =>
      _name.text != _original.name ||
      _description.text != _original.description ||
      _prompt.text != _original.prompt ||
      _rules.text != _original.rules ||
      _targets.length != _original.targets.length ||
      !_targets.containsAll(_original.targets);

  @override
  void dispose() {
    for (final c in [_name, _description, _prompt, _rules]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<bool> _save() async {
    if (_saving) return false;
    if (_name.text.trim().isEmpty) {
      setState(() => _error = '请填写技能名称');
      return false;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.saveSkill(
        _original.copyWith(
          name: _name.text.trim(),
          description: _description.text.trim(),
          prompt: _prompt.text.trim(),
          rules: _rules.text.trim(),
          targets: _targets,
          enabled:
              widget.repository.skills
                  .where((s) => s.id == _original.id)
                  .firstOrNull
                  ?.enabled ??
              _original.enabled,
        ),
      );
      if (!mounted) return false;
      _error = widget.repository.lastError;
    } catch (e) {
      _error = sanitizeErrorText(e.toString(), '技能保存失败');
    }
    if (!mounted) return false;
    setState(() => _saving = false);
    if (_error != null) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(_error!)));
    }
    return _error == null;
  }

  Future<void> _close() async {
    if (_saving || _leaving) return;
    _leaving = true;
    if (_dirty) {
      final choice = await showDialog<_LeaveAction>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('保存技能修改？'),
          content: const Text('当前修改尚未保存。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, _LeaveAction.keepEditing),
              child: const Text('继续编辑'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, _LeaveAction.discard),
              child: const Text('放弃'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, _LeaveAction.save),
              child: const Text('保存'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (choice == null ||
          choice == _LeaveAction.keepEditing ||
          (choice == _LeaveAction.save && !await _save())) {
        _leaving = false;
        return;
      }
    }
    if (mounted) _pop();
  }

  void _pop() {
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_close());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.skill == null ? '新建技能' : '编辑技能'),
          leading: IconButton(
            tooltip: '关闭',
            onPressed: _saving ? null : _close,
            icon: const Icon(Icons.close),
          ),
          actions: [
            TextButton(
              onPressed: _saving
                  ? null
                  : () async {
                      if (await _save() && mounted) _pop();
                    },
              child: const Text('保存'),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_saving) const LinearProgressIndicator(),
            TextField(
              controller: _name,
              enabled: !_saving,
              decoration: const InputDecoration(labelText: '名称（必填）'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _description,
              enabled: !_saving,
              maxLines: 2,
              decoration: const InputDecoration(labelText: '描述'),
            ),
            const SizedBox(height: 16),
            const Text('适用类型'),
            Wrap(
              spacing: 8,
              children: [
                for (final t in SkillTarget.values)
                  FilterChip(
                    label: Text(t.label),
                    selected: _targets.contains(t),
                    onSelected: _saving
                        ? null
                        : (v) => setState(() {
                            if (v) {
                              _targets.add(t);
                            } else {
                              _targets.remove(t);
                            }
                          }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _prompt,
              enabled: !_saving,
              minLines: 5,
              maxLines: null,
              decoration: const InputDecoration(
                labelText: '提示词',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _rules,
              enabled: !_saving,
              minLines: 4,
              maxLines: null,
              decoration: const InputDecoration(
                labelText: '规则',
                alignLabelWithHint: true,
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
