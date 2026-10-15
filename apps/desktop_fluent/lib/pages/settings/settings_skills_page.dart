import 'dart:convert';

import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'widgets/settings_typography.dart';
import 'widgets/settings_conflict_notice.dart';

class SettingsSkillsPage extends StatefulWidget {
  const SettingsSkillsPage({
    super.key,
    required this.repository,
    this.active = true,
  });

  final SkillRepository repository;
  final bool active;

  @override
  State<SettingsSkillsPage> createState() => SettingsSkillsPageState();
}

class SettingsSkillsPageState extends State<SettingsSkillsPage> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _prompt = TextEditingController();
  final _rules = TextEditingController();
  CustomSkill? _editing;
  Set<SkillTarget> _targets = {};
  SkillTarget? _filter;
  bool _enabled = true;
  bool _saving = false;
  bool _checkingLeave = false;
  String? _error;
  String _baseline = '';

  CustomSkill? get _saved => widget.repository.skills
      .where((skill) => skill.id == _editing?.id)
      .firstOrNull;

  bool get _hasConflict =>
      _baseline.isNotEmpty &&
      _saved != null &&
      jsonEncode(_saved!.toJson()) != _baseline;

  CustomSkill get _draft => CustomSkill(
    id: _editing!.id,
    name: _name.text.trim(),
    description: _description.text,
    prompt: _prompt.text,
    rules: _rules.text,
    targets: _targets,
    enabled: _enabled,
  );

  bool get hasUnsavedChanges =>
      _editing != null && jsonEncode(_draft.toJson()) != _baseline;

  @override
  void initState() {
    super.initState();
    for (final controller in [_name, _description, _prompt, _rules]) {
      controller.addListener(_changed);
    }
    widget.repository.addListener(_onRepositoryChanged);
  }

  @override
  void didUpdateWidget(covariant SettingsSkillsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      oldWidget.repository.removeListener(_onRepositoryChanged);
      widget.repository.addListener(_onRepositoryChanged);
      _onRepositoryChanged();
    }
  }

  void _onRepositoryChanged() {
    if (!mounted || _saving || _editing == null || _baseline.isEmpty) return;
    final saved = _saved;
    if (saved == null) {
      setState(() {
        _editing = null;
        _baseline = '';
        _error = null;
        for (final controller in [_name, _description, _prompt, _rules]) {
          controller.clear();
        }
      });
    } else if (!hasUnsavedChanges) {
      _edit(saved);
    } else {
      setState(() {});
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.repository.removeListener(_onRepositoryChanged);
    for (final controller in [_name, _description, _prompt, _rules]) {
      controller.removeListener(_changed);
      controller.dispose();
    }
    super.dispose();
  }

  void _edit(CustomSkill skill) {
    _editing = skill;
    _name.text = skill.name;
    _description.text = skill.description;
    _prompt.text = skill.prompt;
    _rules.text = skill.rules;
    _targets = Set.of(skill.targets);
    _enabled = skill.enabled;
    _baseline = widget.repository.skills.any((s) => s.id == skill.id)
        ? jsonEncode(_draft.toJson())
        : '';
    setState(() => _error = null);
  }

  Future<bool> _save() async {
    if (_saving || _editing == null) return false;
    if (_hasConflict && !await confirmSettingsOverwrite(context)) return false;
    if (!mounted || _editing == null) return false;
    if (_name.text.trim().isEmpty) {
      setState(() => _error = '请输入技能名称');
      return false;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final draft = _draft;
      await widget.repository.saveSkill(draft);
      if (widget.repository.lastError != null) {
        throw StateError(widget.repository.lastError.toString());
      }
      if (!mounted) return false;
      _editing = draft;
      _baseline = jsonEncode(draft.toJson());
      setState(() {});
      return true;
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = '保存失败：${sanitizeErrorText(e.toString(), '请重试')}',
        );
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        _onRepositoryChanged();
      }
    }
  }

  /// 分类、主导航和系统返回共用此门闩。
  Future<bool> confirmLeave({Future<void> Function()? beforePrompt}) async {
    if (_saving || _checkingLeave) return false;
    if (!hasUnsavedChanges) return true;
    _checkingLeave = true;
    try {
      await beforePrompt?.call();
      if (!mounted) return false;
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => ContentDialog(
          title: const Text('技能有未保存的修改'),
          content: const Text('保存后离开，或放弃本次修改。'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop('save'),
              child: const Text('保存'),
            ),
            Button(
              onPressed: () => Navigator.of(ctx).pop('discard'),
              child: const Text('放弃修改'),
            ),
            Button(
              onPressed: () => Navigator.of(ctx).pop('stay'),
              child: const Text('继续编辑'),
            ),
          ],
        ),
      );
      if (!mounted) return false;
      if (action == 'save') return await _save();
      if (action == 'discard') {
        setState(() {
          _editing = null;
          _error = null;
        });
        return true;
      }
      return false;
    } finally {
      _checkingLeave = false;
    }
  }

  Future<void> _select(CustomSkill skill) async {
    if (!await confirmLeave() || !mounted) return;
    final saved = widget.repository.skills.where((s) => s.id == skill.id);
    _edit(saved.isEmpty ? skill : saved.first);
  }

  Future<void> _copy(CustomSkill skill) async {
    if (!await confirmLeave() || !mounted) return;
    final saved = widget.repository.skills.where((s) => s.id == skill.id);
    final source = saved.isEmpty ? skill : saved.first;
    _edit(
      source.copyWith(id: _newId(), name: '${source.name} 副本', enabled: false),
    );
  }

  Future<void> _mutate(Future<void> Function() operation) async {
    if (!await confirmLeave() || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await operation();
      if (widget.repository.lastError != null) {
        throw StateError(widget.repository.lastError.toString());
      }
      if (mounted && _editing != null) {
        final found = widget.repository.skills.where(
          (s) => s.id == _editing!.id,
        );
        if (found.isEmpty) {
          setState(() => _editing = null);
        } else {
          _edit(found.first);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = '操作失败：${sanitizeErrorText(e.toString(), '请重试')}',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(CustomSkill skill) async {
    if (!await confirmLeave() || !mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => ContentDialog(
        title: const Text('删除技能'),
        content: Text('确定删除“${skill.name}”？已保存的历史技能快照仍可查看。'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
          Button(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      await _mutate(() async {
        await widget.repository.deleteSkill(skill.id);
      });
    }
  }

  String _newId() => 'skill_${DateTime.now().microsecondsSinceEpoch}';

  Future<void> _reorder(
    List<CustomSkill> skills,
    int oldIndex,
    int newIndex,
  ) async {
    if (_saving ||
        oldIndex == newIndex ||
        oldIndex < 0 ||
        oldIndex >= skills.length ||
        newIndex < 0 ||
        newIndex >= skills.length) {
      return;
    }
    final source = skills[oldIndex];
    final destination = skills[newIndex];
    await _mutate(() async {
      // 确认保存可能新增技能，因此通过稳定 ID 重新查全局位置。
      final all = widget.repository.skills;
      final sourceGlobal = all.indexWhere((s) => s.id == source.id);
      final destinationGlobal = all.indexWhere((s) => s.id == destination.id);
      if (sourceGlobal < 0 || destinationGlobal < 0) return;
      await widget.repository.moveSkill(
        source.id,
        destinationGlobal - sourceGlobal,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    return PopScope(
      canPop: !widget.active || (!hasUnsavedChanges && !_saving),
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop &&
            widget.active &&
            await confirmLeave() &&
            context.mounted) {
          Navigator.of(context).pop(result);
        }
      },
      child: ListenableBuilder(
        listenable: widget.repository,
        builder: (context, _) => SettingsTypography(
          color: tokens.canvas,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildListPane(tokens),
              Expanded(child: _buildEditorPane(tokens)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListPane(FluentTokens tokens) {
    final skills = widget.repository.skills
        .where((skill) => _filter == null || skill.targets.contains(_filter))
        .toList();
    return SizedBox(
      width: 320,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.canvas,
          border: Border(right: BorderSide(color: tokens.border)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('技能列表', style: context.settingsText.paneTitle),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton(
                        onPressed: _saving
                            ? null
                            : () =>
                                  _select(CustomSkill(id: _newId(), name: '')),
                        child: const Text('新建技能'),
                      ),
                      SizedBox(
                        width: 140,
                        child: ComboBox<String>(
                          value: _filter?.name ?? 'all',
                          isExpanded: true,
                          items: [
                            const ComboBoxItem(
                              value: 'all',
                              child: Text('全部类型'),
                            ),
                            for (final target in SkillTarget.values)
                              ComboBoxItem(
                                value: target.name,
                                child: Text(target.label),
                              ),
                          ],
                          onChanged: _saving
                              ? null
                              : (value) async {
                                  if (await confirmLeave() && mounted) {
                                    setState(
                                      () => _filter = value == 'all'
                                          ? null
                                          : SkillTarget.values.byName(value!),
                                    );
                                  }
                                },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: skills.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(22),
                      child: Text(
                        widget.repository.skills.isEmpty
                            ? '还没有自定义技能，点击新建开始。'
                            : '没有符合当前类型的技能。',
                        style: context.settingsText.caption,
                      ),
                    )
                  : ReorderableList(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
                      itemCount: skills.length,
                      itemBuilder: (context, index) => Padding(
                        key: ValueKey('skill_card_${skills[index].id}'),
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _buildSkillCard(skills, index, tokens),
                      ),
                      // 当前 SDK 的回调已调整向下移动时移除源条目的索引。
                      onReorderItem: (oldIndex, newIndex) =>
                          _reorder(skills, oldIndex, newIndex),
                      proxyDecorator: (child, index, animation) => DecoratedBox(
                        decoration: BoxDecoration(
                          color: tokens.surface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: child,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkillCard(
    List<CustomSkill> skills,
    int index,
    FluentTokens tokens,
  ) {
    final skill = skills[index];
    final selected = _editing?.id == skill.id;
    final background = selected
        ? Color.lerp(tokens.primary, tokens.surface, 0.94)!
        : tokens.surface;
    return Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected
              ? Color.lerp(tokens.primary, tokens.border, 0.5)!
              : tokens.border,
        ),
      ),
      child: Row(
        children: [
          _buildDragHandle(skills, index, tokens),
          Expanded(
            child: Button(
              onPressed: _saving ? null : () => _select(skill),
              style: ButtonStyle(
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 6, vertical: 12),
                ),
                backgroundColor: WidgetStatePropertyAll(background),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      skill.name,
                      style: context.settingsText.label.copyWith(
                        color: tokens.ink,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${skill.targets.map((t) => t.label).join(' · ')}${skill.enabled ? '' : ' · 已停用'}',
                      style: context.settingsText.caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Semantics(
              label: '${skill.name}：${skill.enabled ? '停用技能' : '启用技能'}',
              child: ToggleSwitch(
                key: ValueKey('skill_enabled_${skill.id}'),
                checked: skill.enabled,
                onChanged: _saving
                    ? null
                    : (enabled) => _mutate(
                        () => widget.repository.setEnabled(skill.id, enabled),
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Tooltip(
              message: '技能操作',
              child: DropDownButton(
                key: ValueKey('skill_actions_${skill.id}'),
                disabled: _saving,
                placement: FlyoutPlacementMode.bottomRight,
                menuColor: tokens.surface,
                menuShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: tokens.border),
                ),
                buttonBuilder: (context, onOpen) => SizedBox(
                  width: 28,
                  height: 28,
                  child: IconButton(
                    icon: const Icon(FluentIcons.more, size: 16),
                    onPressed: onOpen,
                    style: ButtonStyle(
                      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                      foregroundColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.disabled)
                            ? tokens.inkMuted
                            : tokens.inkSecondary,
                      ),
                      backgroundColor: WidgetStateProperty.resolveWith((
                        states,
                      ) {
                        if (states.contains(WidgetState.pressed)) {
                          return tokens.ink.withValues(alpha: 0.09);
                        }
                        if (states.contains(WidgetState.hovered) ||
                            states.contains(WidgetState.focused)) {
                          return tokens.ink.withValues(alpha: 0.05);
                        }
                        return Colors.transparent;
                      }),
                      shape: WidgetStateProperty.resolveWith(
                        (states) => RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                          side: states.contains(WidgetState.focused)
                              ? BorderSide(
                                  color: tokens.primary.withValues(alpha: 0.55),
                                )
                              : BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
                items: [
                  MenuFlyoutItem(
                    leading: Icon(
                      FluentIcons.copy,
                      size: 14,
                      color: tokens.inkSecondary,
                    ),
                    text: Text('复制', style: context.settingsText.body),
                    onPressed: _saving ? null : () => _copy(skill),
                  ),
                  MenuFlyoutItem(
                    leading: Icon(
                      FluentIcons.delete,
                      size: 14,
                      color: tokens.danger,
                    ),
                    text: Text(
                      '删除',
                      style: context.settingsText.body.copyWith(
                        color: tokens.danger,
                      ),
                    ),
                    onPressed: _saving ? null : () => _delete(skill),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDragHandle(
    List<CustomSkill> skills,
    int index,
    FluentTokens tokens,
  ) {
    final onMoveUp = !_saving && index > 0
        ? () => _reorder(skills, index, index - 1)
        : null;
    final onMoveDown = !_saving && index < skills.length - 1
        ? () => _reorder(skills, index, index + 1)
        : null;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): () =>
            onMoveUp?.call(),
        const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true): () =>
            onMoveDown?.call(),
      },
      child: Focus(
        canRequestFocus: !_saving,
        includeSemantics: false,
        child: Builder(
          builder: (context) => Semantics(
            key: ValueKey('skill_drag_${skills[index].id}'),
            label: '${skills[index].name}，拖动排序',
            hint: '按 Alt+↑ 或 Alt+↓ 调整顺序',
            focusable: !_saving,
            focused: Focus.of(context).hasFocus,
            customSemanticsActions: {
              const CustomSemanticsAction(label: '上移'): ?onMoveUp,
              const CustomSemanticsAction(label: '下移'): ?onMoveDown,
            },
            child: Tooltip(
              message: '拖动排序',
              excludeFromSemantics: true,
              child: ReorderableDragStartListener(
                index: index,
                enabled: !_saving,
                child: MouseRegion(
                  cursor: _saving
                      ? SystemMouseCursors.basic
                      : SystemMouseCursors.grab,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: Focus.of(context).hasFocus
                            ? tokens.primary
                            : Colors.transparent,
                      ),
                    ),
                    child: Icon(
                      FluentIcons.gripper_dots_vertical,
                      size: 14,
                      color: tokens.inkMuted,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEditorPane(FluentTokens tokens) {
    final error =
        _error ??
        (widget.repository.lastError == null
            ? null
            : '技能加载失败：${widget.repository.lastError}');
    return ColoredBox(
      color: tokens.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_hasConflict)
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const InfoBar(
                    title: Text('本机技能已更新，当前草稿已保留；保存时需要确认覆盖。'),
                    severity: InfoBarSeverity.warning,
                  ),
                  Button(
                    onPressed: _saving
                        ? null
                        : () async {
                            if (!await showFluentConfirmDialog(
                                  context: context,
                                  title: '载入最新技能？',
                                  message: '当前未保存的草稿将被最新技能内容替换。',
                                  confirmLabel: '载入最新',
                                ) ||
                                !mounted) {
                              return;
                            }
                            final saved = _saved;
                            if (saved != null) _edit(saved);
                          },
                    child: const Text('载入最新'),
                  ),
                ],
              ),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
              child: InfoBar(
                title: Text(error),
                severity: InfoBarSeverity.error,
              ),
            ),
          Expanded(
            child: _editing == null
                ? Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 20,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            FluentIcons.edit,
                            size: 32,
                            color: tokens.inkMuted,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '选择技能进行编辑，修改后请显式保存。',
                            textAlign: TextAlign.center,
                            style: context.settingsText.caption,
                          ),
                        ],
                      ),
                    ),
                  )
                : CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
                        sliver: SliverList.list(
                          children: [
                            Text('编辑技能', style: context.settingsText.pageTitle),
                            const SizedBox(height: 4),
                            Text(
                              '启用的技能按顺序自动应用到所选类型的生成与润色。',
                              style: context.settingsText.caption,
                            ),
                            const SizedBox(height: 20),
                            ..._buildFormFields(),
                          ],
                        ),
                      ),
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Padding(
                          // 将底部留白计入剩余高度，并预留 1px 避免边界溢出。
                          padding: const EdgeInsets.fromLTRB(28, 0, 28, 17),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 180),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text('规则', style: context.settingsText.label),
                                const SizedBox(height: 6),
                                Expanded(
                                  child: TextBox(
                                    key: const ValueKey('skill_rules'),
                                    controller: _rules,
                                    enabled: !_saving,
                                    minLines: null,
                                    maxLines: null,
                                    expands: true,
                                    textAlignVertical: TextAlignVertical.top,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          if (_editing != null) _buildSaveBar(tokens),
        ],
      ),
    );
  }

  List<Widget> _buildFormFields() => [
    InfoLabel(
      label: '名称',
      labelStyle: context.settingsText.label,
      child: TextBox(
        key: const ValueKey('skill_name'),
        controller: _name,
        enabled: !_saving,
      ),
    ),
    const SizedBox(height: 12),
    InfoLabel(
      label: '描述',
      labelStyle: context.settingsText.label,
      child: TextBox(controller: _description, enabled: !_saving, maxLines: 2),
    ),
    const SizedBox(height: 12),
    Text('应用类型', style: context.settingsText.label),
    const SizedBox(height: 8),
    Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        for (final target in SkillTarget.values)
          Checkbox(
            content: Text(target.label),
            checked: _targets.contains(target),
            onChanged: _saving
                ? null
                : (checked) => setState(() {
                    if (checked == true) {
                      _targets.add(target);
                    } else {
                      _targets.remove(target);
                    }
                  }),
          ),
      ],
    ),
    const SizedBox(height: 12),
    InfoLabel(
      label: '提示词',
      labelStyle: context.settingsText.label,
      child: TextBox(
        controller: _prompt,
        enabled: !_saving,
        minLines: 5,
        maxLines: 10,
      ),
    ),
    const SizedBox(height: 12),
  ];

  Widget _buildSaveBar(FluentTokens tokens) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 16),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: [
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中…' : '保存技能'),
          ),
          if (hasUnsavedChanges) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text('有未保存的修改', style: context.settingsText.caption),
            ),
          ],
        ],
      ),
    );
  }
}
