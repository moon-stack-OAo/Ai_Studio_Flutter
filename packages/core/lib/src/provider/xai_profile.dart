import 'provider_type.dart';

bool _isNativeXaiBaseUrl(String? baseUrl) {
  final base = (baseUrl ?? '').toLowerCase();
  return base.contains('api.x.ai') ||
      base.contains('.x.ai/') ||
      base.endsWith('.x.ai');
}

/// 官方 xAI（类型或 api.x.ai），完成态通常直接给 `video.url`，无需 `/content`。
bool isNativeXaiVideoProvider({
  ProviderType? providerType,
  String? baseUrl,
}) {
  if (providerType == ProviderType.xai) return true;
  return _isNativeXaiBaseUrl(baseUrl);
}

/// 是否应按 xAI **创建**协议处理（`POST /videos/generations`）。
///
/// 覆盖：
/// - 官方 xAI（类型 / api.x.ai）
/// - 视频模型名含 `imagine-video`（中转常把类型标成 OpenAI 兼容）
///
/// 注意：中转仅模型名命中时，完成态仍可能走 `/content`，见 [shouldFetchVideoContent]。
bool isXaiVideoProvider({
  ProviderType? providerType,
  String? baseUrl,
  String? videoModel,
}) {
  if (isNativeXaiVideoProvider(
    providerType: providerType,
    baseUrl: baseUrl,
  )) {
    return true;
  }
  final video = (videoModel ?? '').trim().toLowerCase();
  return video.contains('imagine-video');
}
