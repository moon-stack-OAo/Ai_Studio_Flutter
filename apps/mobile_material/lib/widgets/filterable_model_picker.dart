import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';

/// Material 触控版可搜索模型下拉（对齐 filterable+tag；勿抄 Fluent 控件）。
class FilterableModelPicker extends StatefulWidget {
  const FilterableModelPicker({
    super.key,
    required this.controller,
    required this.options,
    required this.placeholder,
    required this.onChanged,
    this.enabled = true,
    this.allowClear = false,
    this.clearLabel = '不使用',
  });

  final TextEditingController controller;
  final List<ModelSelectOption> options;
  final String placeholder;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final bool allowClear;
  final String clearLabel;

  @override
  State<FilterableModelPicker> createState() => _FilterableModelPickerState();
}

class _FilterableModelPickerState extends State<FilterableModelPicker> {
  final _focus = FocusNode();
  late String _tagText;
  String _query = '';
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _tagText = widget.controller.text.trim();
    _query = widget.controller.text;
    widget.controller.addListener(_onControllerTick);
    _focus.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant FilterableModelPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerTick);
      widget.controller.addListener(_onControllerTick);
      _tagText = widget.controller.text.trim();
      _query = widget.controller.text;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerTick);
    _focus
      ..removeListener(_onFocusChanged)
      ..dispose();
    super.dispose();
  }

  void _onControllerTick() {
    final next = widget.controller.text.trim();
    if (next == _tagText) return;
    setState(() => _tagText = next);
  }

  void _onFocusChanged() {
    if (_focus.hasFocus) {
      _open();
    } else {
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (!mounted || _focus.hasFocus) return;
        setState(() => _expanded = false);
        _commit(widget.controller.text);
      });
    }
  }

  void _open() {
    if (!widget.enabled) return;
    if (widget.options.isEmpty && !widget.allowClear) return;
    if (_expanded) return;
    setState(() => _expanded = true);
  }

  void _toggle() {
    if (!widget.enabled) return;
    if (widget.options.isEmpty && !widget.allowClear) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先点击「拉取模型」')),
      );
      return;
    }
    setState(() => _expanded = !_expanded);
    if (_expanded) _focus.requestFocus();
  }

  void _commit(String value) {
    final v = value.trim();
    if (widget.controller.text != v) {
      widget.controller.value = TextEditingValue(
        text: v,
        selection: TextSelection.collapsed(offset: v.length),
      );
    }
    setState(() {
      _tagText = v;
      _query = v;
      _expanded = false;
    });
    widget.onChanged(v);
  }

  List<ModelSelectOption> get _filtered {
    final q = _query.trim().toLowerCase();
    if (widget.options.isEmpty) return const [];
    if (q.isEmpty) return widget.options;
    return [
      for (final o in widget.options)
        if (o.value.toLowerCase().contains(q) ||
            o.label.toLowerCase().contains(q))
          o,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    final filtered = _filtered;
    final showList = _expanded && (widget.options.isNotEmpty || widget.allowClear);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: widget.controller,
          focusNode: _focus,
          enabled: widget.enabled,
          style: TextStyle(
            fontSize: 14,
            color: tokens.ink,
          ).withMonoFont(tokens),
          decoration: InputDecoration(
            hintText: widget.options.isEmpty
                ? '${widget.placeholder}（先拉取模型）'
                : '搜索已拉取模型…',
            isDense: true,
            suffixIcon: IconButton(
              tooltip: showList ? '收起模型列表' : '展开模型列表',
              icon: Icon(
                showList ? Icons.expand_less : Icons.expand_more,
                color: widget.options.isEmpty && !widget.allowClear
                    ? tokens.inkMuted.withValues(alpha: 0.45)
                    : tokens.inkMuted,
              ),
              onPressed: widget.enabled ? _toggle : null,
            ),
          ),
          onTap: widget.enabled ? _open : null,
          onChanged: widget.enabled
              ? (text) {
                  setState(() {
                    _query = text;
                    _tagText = text.trim();
                    if (widget.options.isNotEmpty || widget.allowClear) {
                      _expanded = true;
                    }
                  });
                  widget.onChanged(text);
                }
              : null,
          onSubmitted: widget.enabled
              ? (text) {
                  final list = _filtered;
                  if (list.length == 1) {
                    _commit(list.first.value);
                  } else {
                    _commit(text);
                  }
                }
              : null,
        ),
        if (showList) ...[
          const SizedBox(height: 6),
          _ModelComboList(
            items: filtered,
            selected: _tagText,
            allowClear: widget.allowClear,
            clearLabel: widget.clearLabel,
            emptyHint: _query.trim().isEmpty
                ? '无可用模型'
                : '无匹配「${_query.trim()}」· 回车可使用该名称',
            onPick: _commit,
          ),
        ],
        if (widget.options.isEmpty && !widget.allowClear) ...[
          const SizedBox(height: 6),
          Text(
            '拉取模型后，点击输入框或 ▼ 展开列表；输入即过滤。',
            style: TextStyle(
              fontSize: 11,
              color: tokens.inkMuted,
              fontFamily: tokens.fontFamily,
            ),
          ),
        ],
        if (_tagText.isNotEmpty) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: InputChip(
              label: Text(
                _tagText,
                style: TextStyle(
                  fontSize: 12,
                ).withMonoFont(tokens),
              ),
              onDeleted: widget.enabled ? () => _commit('') : null,
              deleteButtonTooltipMessage: '清除所选模型',
              deleteIconColor: tokens.inkMuted,
              side: BorderSide(color: tokens.border),
              backgroundColor: tokens.surfaceMuted,
            ),
          ),
        ],
      ],
    );
  }
}

class _ModelComboList extends StatelessWidget {
  const _ModelComboList({
    required this.items,
    required this.selected,
    required this.emptyHint,
    required this.onPick,
    required this.allowClear,
    required this.clearLabel,
  });

  final List<ModelSelectOption> items;
  final String selected;
  final String emptyHint;
  final ValueChanged<String> onPick;
  final bool allowClear;
  final String clearLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    final showEmpty = items.isEmpty && !allowClear;

    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: showEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Text(
                emptyHint,
                style: TextStyle(
                  fontSize: 12,
                  color: tokens.inkMuted,
                  fontFamily: tokens.fontFamily,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(4),
              shrinkWrap: true,
              children: [
                if (allowClear)
                  ListTile(
                    dense: true,
                    selected: selected.isEmpty,
                    title: Text(
                      clearLabel,
                      style: TextStyle(
                        fontSize: 13,
                        color: tokens.inkMuted,
                        fontFamily: tokens.fontFamily,
                      ),
                    ),
                    onTap: () => onPick(''),
                  ),
                if (items.isEmpty && allowClear)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Text(
                      emptyHint,
                      style: TextStyle(
                        fontSize: 12,
                        color: tokens.inkMuted,
                        fontFamily: tokens.fontFamily,
                      ),
                    ),
                  )
                else
                  for (final o in items)
                    ListTile(
                      dense: true,
                      selected: o.value == selected,
                      title: Text(
                        o.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: o.manual
                            ? TextStyle(
                                fontSize: 13,
                                fontFamily: tokens.fontFamily,
                                color: tokens.inkMuted,
                                fontWeight: o.value == selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              )
                            : TextStyle(
                                fontSize: 13,
                                color: tokens.ink,
                                fontWeight: o.value == selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ).withMonoFont(tokens),
                      ),
                      onTap: () => onPick(o.value),
                    ),
              ],
            ),
    );
  }
}
