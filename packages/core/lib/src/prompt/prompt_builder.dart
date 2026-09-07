import 'prompt_dimensions.dart';
import 'prompt_presets.dart';

const String _joiner = '，';

PromptDimensionOption? _findOption(
  PromptDimensionGroup group,
  String? optionId,
) {
  if (optionId == null || optionId.isEmpty) return null;
  for (final o in group.options) {
    if (o.id == optionId) return o;
  }
  return null;
}

List<String> _collectTexts(
  List<PromptDimensionGroup> groups,
  Map<String, Object?> selection,
) {
  final texts = <String>[];
  for (final group in groups) {
    final raw = selection[group.id];
    if (raw == null) continue;
    if (raw is String && raw.isEmpty) continue;

    if (group.multiple && raw is List) {
      for (final id in raw) {
        final opt = _findOption(group, id?.toString());
        if (opt != null && opt.text.isNotEmpty) texts.add(opt.text);
      }
      continue;
    }

    final id = raw is List
        ? (raw.isEmpty ? null : raw.first?.toString())
        : raw.toString();
    final opt = _findOption(group, id);
    if (opt != null && opt.text.isNotEmpty) texts.add(opt.text);
  }
  return texts;
}

/// 按维度选中项拼装提示词（对齐现网 buildPromptFromSelection）。
///
/// [selection] 值为单选 `String?` 或多选 `List<String>`。
String buildPromptFromSelection(
  PromptDomain domain,
  Map<String, Object?> selection, {
  String? extraText,
  String? mode,
}) {
  final groups = getPromptDimensions(domain);
  final parts = _collectTexts(groups, selection);

  final extra = (extraText ?? '').trim();
  if (extra.isNotEmpty) parts.add(extra);

  if (parts.isEmpty) return '';
  return parts.join(_joiner);
}

Map<String, Object?> _createEmptySelection(List<PromptDimensionGroup> groups) {
  final sel = <String, Object?>{};
  for (final g in groups) {
    sel[g.id] = g.multiple ? <String>[] : null;
  }
  return sel;
}

/// 结构化提示词拼装状态（对齐现网 usePromptBuilder）。
class PromptBuilderState {
  PromptBuilderState(this.domain) {
    selection = _createEmptySelection(dimensions);
  }

  final PromptDomain domain;

  late Map<String, Object?> selection;

  List<PromptDimensionGroup> get dimensions => getPromptDimensions(domain);

  String get preview => buildPromptFromSelection(domain, selection);

  PromptDimensionGroup? _group(String groupId) {
    for (final g in dimensions) {
      if (g.id == groupId) return g;
    }
    return null;
  }

  /// 设置选项；多选时为 toggle 入/出列表，单选直接赋值。
  void setOption(String groupId, String? optionId) {
    final group = _group(groupId);
    if (group == null) return;

    if (group.multiple) {
      final current = selection[groupId];
      final list = current is List
          ? List<String>.from(current.map((e) => e.toString()))
          : <String>[];
      if (optionId == null || optionId.isEmpty) {
        selection[groupId] = list;
        return;
      }
      final idx = list.indexOf(optionId);
      if (idx >= 0) {
        list.removeAt(idx);
      } else {
        list.add(optionId);
      }
      selection[groupId] = list;
      return;
    }

    selection[groupId] = optionId;
  }

  /// 切换选项；单选再点同一项则取消。
  void toggleOption(String groupId, String optionId) {
    final group = _group(groupId);
    if (group == null) return;

    if (group.multiple) {
      setOption(groupId, optionId);
      return;
    }

    selection[groupId] = selection[groupId] == optionId ? null : optionId;
  }

  void clear() {
    selection = _createEmptySelection(dimensions);
  }

  String build([String? extraText]) {
    return buildPromptFromSelection(
      domain,
      selection,
      extraText: extraText,
    );
  }
}
