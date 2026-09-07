import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// 对齐原型 / 现网 filterable+tag：
/// - 点击或聚焦输入框 → 展开下方列表
/// - 边输入边过滤
/// - 可选手动输入不在列表中的模型名
class FilterableModelPicker extends StatefulWidget {
  const FilterableModelPicker({
    super.key,
    required this.controller,
    required this.options,
    required this.placeholder,
    required this.onChanged,
    this.enabled = true,
  });

  final TextEditingController controller;
  final List<ModelSelectOption> options;
  final String placeholder;
  final ValueChanged<String> onChanged;
  final bool enabled;

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
      // 失焦稍后收起，避免点列表项时焦点先丢导致点不到
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (!mounted || _focus.hasFocus) return;
        setState(() => _expanded = false);
        _commit(widget.controller.text);
      });
    }
  }

  void _open() {
    if (!widget.enabled || widget.options.isEmpty) return;
    if (_expanded) return;
    setState(() => _expanded = true);
  }

  void _toggle() {
    if (!widget.enabled) return;
    if (widget.options.isEmpty) {
      displayInfoBar(
        context,
        builder: (context, close) => InfoBar(
          title: const Text('请先点击「拉取模型」'),
          severity: InfoBarSeverity.info,
          onClose: close,
        ),
      );
      return;
    }
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _focus.requestFocus();
    }
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
    final tokens = fluentTokensOf(context);
    final filtered = _filtered;
    final showList = _expanded && widget.options.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextBox(
          controller: widget.controller,
          focusNode: _focus,
          enabled: widget.enabled,
          placeholder: widget.options.isEmpty
              ? '${widget.placeholder}（先拉取模型）'
              : '搜索已拉取模型…',
          style: TextStyle(
            fontSize: 13,
            color: tokens.ink,
          ).withMonoFont(tokens),
          onTap: widget.enabled ? _open : null,
          onChanged: widget.enabled
              ? (text) {
                  setState(() {
                    _query = text;
                    _tagText = text.trim();
                    if (widget.options.isNotEmpty) _expanded = true;
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
          suffix: IconButton(
            icon: Icon(
              showList ? FluentIcons.chevron_up : FluentIcons.chevron_down,
              size: 10,
              color: widget.options.isEmpty
                  ? tokens.inkMuted.withValues(alpha: 0.45)
                  : tokens.inkMuted,
            ),
            onPressed: widget.enabled ? _toggle : null,
          ),
        ),
        if (showList) ...[
          const SizedBox(height: 6),
          _ModelComboList(
            items: filtered,
            selected: _tagText,
            emptyHint: _query.trim().isEmpty
                ? '无可用模型'
                : '无匹配「${_query.trim()}」· 回车可使用该名称',
            onPick: _commit,
          ),
        ],
        if (widget.options.isEmpty) ...[
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
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: _ModelTag(
              label: _tagText,
              onClear: widget.enabled ? () => _commit('') : null,
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
  });

  final List<ModelSelectOption> items;
  final String selected;
  final String emptyHint;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    return Container(
      constraints: const BoxConstraints(maxHeight: 168),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: items.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Text(
                emptyHint,
                style: TextStyle(
                  fontSize: 12,
                  color: tokens.inkMuted,
                  fontFamily: tokens.fontFamily,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(4),
              shrinkWrap: true,
              itemCount: items.length,
              itemBuilder: (context, index) {
                final o = items[index];
                final active = o.value == selected;
                return HoverButton(
                  onPressed: () => onPick(o.value),
                  builder: (context, states) {
                    final hovered = states.isHovered || states.isPressed;
                    final bg = active
                        ? Color.lerp(tokens.primary, tokens.surface, 0.86)
                        : hovered
                            ? Color.lerp(tokens.ink, tokens.surface, 0.94)
                            : Colors.transparent;
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        o.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: o.manual
                            ? TextStyle(
                                fontSize: 13,
                                fontFamily: tokens.fontFamily,
                                color: tokens.inkMuted,
                                fontWeight: active
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              )
                            : TextStyle(
                                fontSize: 13,
                                color: tokens.ink,
                                fontWeight: active
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ).withMonoFont(tokens),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

class _ModelTag extends StatelessWidget {
  const _ModelTag({
    required this.label,
    this.onClear,
  });

  final String label;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    // Windows：小 IconButton + 动态 tag 易触发 Overlay/AXTree 异常；仅局部排除。
    return ExcludeSemantics(
      child: Container(
        padding: const EdgeInsetsDirectional.only(start: 8, end: 2),
        decoration: BoxDecoration(
          color: tokens.surfaceMuted,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: tokens.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: tokens.inkSecondary,
              ).withMonoFont(tokens),
            ),
            if (onClear != null)
              IconButton(
                icon: Icon(
                  FluentIcons.chrome_close,
                  size: 8,
                  color: tokens.inkMuted,
                ),
                onPressed: onClear,
              ),
          ],
        ),
      ),
    );
  }
}
