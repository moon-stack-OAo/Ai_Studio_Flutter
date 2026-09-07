import '../security/url_safety.dart';

/// OpenAI 兼容端点 URL / 鉴权头工具（不自动补 `/v1`）。

/// 去掉首尾空白与尾部 `/`。
String normalizeBaseUrl(String baseUrl) {
  return baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
}

/// 校验提供商 Base URL（硬拦危险 scheme / 元数据地址）。
void assertSafeBaseUrl(String baseUrl) {
  final trimmed = normalizeBaseUrl(baseUrl);
  if (trimmed.isEmpty) {
    throw const UrlSafetyException('请先填写 Base URL');
  }
  assertSafeFetchUrl(trimmed);
}

/// `{baseUrl}/chat/completions`
Uri chatCompletionsUri(String baseUrl) {
  final trimmed = normalizeBaseUrl(baseUrl);
  return Uri.parse('$trimmed/chat/completions');
}

/// `{baseUrl}/models`
Uri modelsUri(String baseUrl) {
  final trimmed = normalizeBaseUrl(baseUrl);
  return Uri.parse('$trimmed/models');
}

/// `{baseUrl}/images/generations`
Uri imageGenerationsUri(String baseUrl) {
  final trimmed = normalizeBaseUrl(baseUrl);
  return Uri.parse('$trimmed/images/generations');
}

/// `{baseUrl}/images/edits`
Uri imageEditsUri(String baseUrl) {
  final trimmed = normalizeBaseUrl(baseUrl);
  return Uri.parse('$trimmed/images/edits');
}

/// OpenAI：`{baseUrl}/videos`
Uri videosUri(String baseUrl) {
  final trimmed = normalizeBaseUrl(baseUrl);
  return Uri.parse('$trimmed/videos');
}

/// xAI：`{baseUrl}/videos/generations`
Uri videoGenerationsUri(String baseUrl) {
  final trimmed = normalizeBaseUrl(baseUrl);
  return Uri.parse('$trimmed/videos/generations');
}

/// `{baseUrl}/videos/{id}`
Uri videoJobUri(String baseUrl, String jobId) {
  final trimmed = normalizeBaseUrl(baseUrl);
  final id = Uri.encodeComponent(jobId.trim());
  return Uri.parse('$trimmed/videos/$id');
}

/// OpenAI content：`{baseUrl}/videos/{id}/content`
Uri videoContentUri(String baseUrl, String jobId) {
  final trimmed = normalizeBaseUrl(baseUrl);
  final id = Uri.encodeComponent(jobId.trim());
  return Uri.parse('$trimmed/videos/$id/content');
}

/// 鉴权头：`Authorization: Bearer` + `x-api-key`（key 非空时一并带上）。
Map<String, String> authHeaders(
  String apiKey, {
  Map<String, String> extra = const {},
}) {
  final headers = Map<String, String>.from(extra);
  final key = apiKey.trim();
  if (key.isNotEmpty) {
    headers['Authorization'] = 'Bearer $key';
    headers['x-api-key'] = key;
  }
  return headers;
}
