import 'provider_connection.dart';

/// 模型粗分类（对齐现网 `models.js`；中转站命名不一，仅作 UI 筛选）。
enum ModelKind {
  chat,
  image,
  video,
  other,
}

const _videoHints = <String>[
  'video',
  'sora',
  'veo',
  'imagine-video',
  'seedance',
  'kling',
  'runway',
  'luma',
  'hailuo',
  'minimax-video',
];

const _imageHints = <String>[
  'dall-e',
  'gpt-image',
  'imagen',
  'image',
  'flux',
  'midjourney',
  'stable-diffusion',
  'sdxl',
  'grok-imagine',
  'banana',
];

const _chatExclude = <String>[
  'embedding',
  'whisper',
  'tts',
  'transcribe',
  'moderation',
  'realtime',
  'video',
  'sora',
];

bool _includesAny(String id, List<String> keywords) {
  for (final k in keywords) {
    if (id.contains(k)) return true;
  }
  return false;
}

/// 按 id 粗分 chat / image / video / other。
ModelKind classifyModelId(String? modelId) {
  final id = (modelId ?? '').trim().toLowerCase();
  if (id.isEmpty) return ModelKind.other;
  if (_includesAny(id, _videoHints)) return ModelKind.video;
  if (_includesAny(id, _imageHints)) return ModelKind.image;
  if (_includesAny(id, _chatExclude)) return ModelKind.other;
  return ModelKind.chat;
}

/// 按能力筛选模型列表。
List<ProviderModelInfo> filterModelsByKind(
  Iterable<ProviderModelInfo> models,
  ModelKind kind,
) {
  if (kind == ModelKind.other) {
    return List<ProviderModelInfo>.from(models);
  }
  return [
    for (final m in models)
      if (classifyModelId(m.id) == kind) m,
  ];
}

/// 下拉选项：去重；若当前值不在列表中则追加「手动」项（对齐现网 tag）。
List<ModelSelectOption> toSelectOptions(
  Iterable<ProviderModelInfo> models, {
  String? current,
  String? fallbackLabel,
}) {
  final map = <String, ModelSelectOption>{};
  for (final item in models) {
    final id = item.id.trim();
    if (id.isEmpty) continue;
    map.putIfAbsent(
      id,
      () => ModelSelectOption(value: id, label: id, manual: false),
    );
  }
  final cur = current?.trim() ?? '';
  if (cur.isNotEmpty && !map.containsKey(cur)) {
    map[cur] = ModelSelectOption(
      value: cur,
      label: fallbackLabel ?? '$cur（手动）',
      manual: true,
    );
  }
  return map.values.toList();
}

/// 能力下拉用：先按 kind 筛；空则回退全量（中转命名不规范时）。
List<ModelSelectOption> modelOptionsByKind(
  Iterable<ProviderModelInfo> models,
  ModelKind kind, {
  String? current,
}) {
  var filtered = filterModelsByKind(models, kind);
  if (filtered.isEmpty && models.isNotEmpty) {
    filtered = List<ProviderModelInfo>.from(models);
  }
  return toSelectOptions(filtered, current: current);
}

class ModelSelectOption {
  const ModelSelectOption({
    required this.value,
    required this.label,
    this.manual = false,
  });

  final String value;
  final String label;
  final bool manual;
}
