import '../provider/provider_config.dart';
import '../provider/provider_type.dart';

/// 生图质量选项（对齐 OpenAI / xAI `quality` 字段）。
class ImageQualityOption {
  const ImageQualityOption({required this.label, required this.value});

  final String label;
  final String value;
}

/// 标准 / 高清 / 极致 → medium / high / low 不匹配 API；与现网一致用 low/medium/high。
const List<ImageQualityOption> imageQualityOptions = [
  ImageQualityOption(label: '低', value: 'low'),
  ImageQualityOption(label: '标准', value: 'medium'),
  ImageQualityOption(label: '高', value: 'high'),
];

const String defaultImageQuality = 'medium';

/// 是否向生图接口附带 quality（自定义中转一律不传，避免拒参）。
bool supportsImageQuality({
  required bool builtin,
  required ProviderType type,
  required String imageModel,
}) {
  if (!builtin) return false;
  switch (type) {
    case ProviderType.openai:
      return true;
    case ProviderType.xai:
      final model = imageModel.toLowerCase();
      return model.contains('imagine-image-2') || model.contains('2.0');
    case ProviderType.openaiCompatible:
      return false;
  }
}

bool supportsImageQualityForProvider(ProviderConfig? provider) {
  if (provider == null) return false;
  return supportsImageQuality(
    builtin: provider.builtin,
    type: provider.type,
    imageModel: provider.imageModel,
  );
}

String? imageQualityLabel(String? value) {
  final v = (value ?? '').trim();
  if (v.isEmpty) return null;
  for (final o in imageQualityOptions) {
    if (o.value == v) return o.label;
  }
  return v;
}
