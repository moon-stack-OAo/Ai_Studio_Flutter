import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../chat/chat_errors.dart';
import '../openai/openai_urls.dart';
import '../provider/provider_repository.dart';
import '../provider/provider_type.dart';
import '../security/safe_http_client.dart';
import '../security/url_safety.dart';
import 'image_models.dart';

/// 默认生图超时（约 180s）。
const Duration defaultImageTimeout = Duration(seconds: 180);

/// OpenAI / xAI 兼容生图客户端。
class OpenAiCompatibleImageClient {
  OpenAiCompatibleImageClient({
    http.Client? client,
    this.timeout = defaultImageTimeout,
  })  : _ownedClient = client == null,
        _client = client ?? createSafeHttpClient();

  final http.Client _client;
  final bool _ownedClient;
  final Duration timeout;

  bool get ownsClient => _ownedClient;

  void close() {
    if (_ownedClient) {
      _client.close();
    }
  }

  /// 使用 [ActiveImageCredentials] 文生图。
  Future<List<ImageRef>> generateTextToImageWithCredentials(
    ActiveImageCredentials credentials, {
    required String prompt,
    int n = 1,
    String? size,
    String? aspectRatio,
    String? quality,
    String responseFormat = 'b64_json',
    Duration? timeout,
    http.Client? client,
  }) {
    return generateTextToImage(
      baseUrl: credentials.baseUrl,
      apiKey: credentials.apiKey,
      model: credentials.imageModel,
      providerType: credentials.type,
      prompt: prompt,
      n: n,
      size: size,
      aspectRatio: aspectRatio,
      quality: quality,
      responseFormat: responseFormat,
      timeout: timeout,
      client: client,
    );
  }

  /// 文生图：POST `{base}/images/generations`。
  ///
  /// OpenAI 系写 [size]；xAI 或显式传入 [aspectRatio] 时写 `aspect_ratio`。
  Future<List<ImageRef>> generateTextToImage({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String prompt,
    ProviderType providerType = ProviderType.openaiCompatible,
    int n = 1,
    String? size,
    String? aspectRatio,
    String? quality,
    String responseFormat = 'b64_json',
    Duration? timeout,
    http.Client? client,
  }) async {
    final modelId = model.trim();
    if (modelId.isEmpty) {
      throw const ChatApiException('请先设置生图模型');
    }
    if (normalizeBaseUrl(baseUrl).isEmpty) {
      throw const ChatApiException('请先填写 Base URL');
    }
    try {
      assertSafeBaseUrl(baseUrl);
    } on UrlSafetyException catch (e) {
      throw ChatApiException(e.message);
    }
    final text = prompt.trim();
    if (text.isEmpty) {
      throw const ChatApiException('请输入提示词');
    }

    final useAspect = providerType == ProviderType.xai ||
        (aspectRatio != null && aspectRatio.trim().isNotEmpty);

    final body = <String, dynamic>{
      'model': modelId,
      'prompt': text,
      'n': n.clamp(1, 10),
      'response_format': responseFormat,
    };
    if (useAspect) {
      final ar = (aspectRatio ?? '').trim();
      if (ar.isNotEmpty) body['aspect_ratio'] = ar;
    } else {
      final sz = (size ?? '').trim();
      if (sz.isNotEmpty) body['size'] = sz;
    }
    final q = quality?.trim();
    if (q != null && q.isNotEmpty) body['quality'] = q;

    return _postJson(
      uri: imageGenerationsUri(baseUrl),
      apiKey: apiKey,
      body: body,
      timeout: timeout,
      client: client,
    );
  }

  /// 图生图：OpenAI multipart `/images/edits`；xAI JSON + `image.url` dataUrl。
  Future<List<ImageRef>> editImage({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String prompt,
    required Uint8List imageBytes,
    String imageFileName = 'image.png',
    ProviderType providerType = ProviderType.openaiCompatible,
    int n = 1,
    String? size,
    String? aspectRatio,
    String? quality,
    String responseFormat = 'b64_json',
    Duration? timeout,
    http.Client? client,
  }) async {
    final modelId = model.trim();
    if (modelId.isEmpty) {
      throw const ChatApiException('请先设置生图模型');
    }
    if (normalizeBaseUrl(baseUrl).isEmpty) {
      throw const ChatApiException('请先填写 Base URL');
    }
    try {
      assertSafeBaseUrl(baseUrl);
    } on UrlSafetyException catch (e) {
      throw ChatApiException(e.message);
    }
    final text = prompt.trim();
    if (text.isEmpty) {
      throw const ChatApiException('请输入提示词');
    }
    if (imageBytes.isEmpty) {
      throw const ChatApiException('请先选择参考图');
    }

    final effectiveClient = client ?? _client;
    final reqTimeout = timeout ?? this.timeout;
    final uri = imageEditsUri(baseUrl);

    if (providerType == ProviderType.xai) {
      final dataUrl =
          'data:image/png;base64,${base64Encode(imageBytes)}';
      final body = <String, dynamic>{
        'model': modelId,
        'prompt': text,
        'n': n.clamp(1, 10),
        'response_format': responseFormat,
        'image': {
          'url': dataUrl,
          'type': 'image_url',
        },
      };
      final ar = aspectRatio?.trim();
      if (ar != null && ar.isNotEmpty) body['aspect_ratio'] = ar;
      final q = quality?.trim();
      if (q != null && q.isNotEmpty) body['quality'] = q;
      return _postJson(
        uri: uri,
        apiKey: apiKey,
        body: body,
        timeout: timeout,
        client: client,
      );
    }

    final headers = authHeaders(apiKey);
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(headers)
      ..fields['model'] = modelId
      ..fields['prompt'] = text
      ..fields['n'] = '${n.clamp(1, 10)}'
      ..fields['response_format'] = responseFormat
      ..files.add(
        http.MultipartFile.fromBytes(
          'image',
          imageBytes,
          filename: imageFileName,
        ),
      );
    final sz = (size ?? '').trim();
    if (sz.isNotEmpty) request.fields['size'] = sz;
    final q = quality?.trim();
    if (q != null && q.isNotEmpty) request.fields['quality'] = q;

    late http.StreamedResponse streamed;
    try {
      streamed = await effectiveClient.send(request).timeout(reqTimeout);
    } on TimeoutException {
      throw const ChatApiException('请求超时，请稍后重试或增大超时时间');
    } catch (e) {
      if (isAbortLike(e)) throw toAbortError();
      throw ChatApiException(describeNetworkError(e));
    }

    final raw = await _readBody(streamed);
    return _parseResponse(streamed.statusCode, raw);
  }

  Future<List<ImageRef>> _postJson({
    required Uri uri,
    required String apiKey,
    required Map<String, dynamic> body,
    Duration? timeout,
    http.Client? client,
  }) async {
    final effectiveClient = client ?? _client;
    final reqTimeout = timeout ?? this.timeout;
    final headers = authHeaders(
      apiKey,
      extra: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    );

    late http.Response response;
    try {
      response = await effectiveClient
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(reqTimeout);
    } on TimeoutException {
      throw const ChatApiException('请求超时，请稍后重试或增大超时时间');
    } catch (e) {
      if (isAbortLike(e)) throw toAbortError();
      throw ChatApiException(describeNetworkError(e));
    }

    return _parseResponse(response.statusCode, response.body);
  }

  Future<String> _readBody(http.StreamedResponse streamed) async {
    try {
      return await streamed.stream.bytesToString();
    } catch (e) {
      if (isAbortLike(e)) throw toAbortError();
      return '';
    }
  }

  List<ImageRef> _parseResponse(int statusCode, String raw) {
    if (statusCode < 200 || statusCode >= 300) {
      String bodyMsg = '';
      try {
        final decoded = jsonDecode(raw);
        bodyMsg = extractApiErrorMessage(decoded);
      } catch (_) {
        bodyMsg = raw.trim();
        if (bodyMsg.length > 300) bodyMsg = bodyMsg.substring(0, 300);
      }
      final msg = httpStatusErrorMessage(statusCode, bodyMsg);
      final cleaned = sanitizeErrorText(msg, '');
      throw ChatApiException(
        cleaned.isNotEmpty ? cleaned : 'HTTP $statusCode',
        statusCode: statusCode,
      );
    }

    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      throw const ChatApiException('响应解析失败');
    }
    return normalizeImageResponse(decoded);
  }
}

/// 归一化上游 `data[]` → [ImageRef] 列表。
List<ImageRef> normalizeImageResponse(Object? data) {
  if (data is! Map) return const [];
  final list = data['data'];
  if (list is! List) return const [];
  final out = <ImageRef>[];
  for (final item in list) {
    if (item is! Map) continue;
    final map = Map<String, dynamic>.from(item);
    final revised = map['revised_prompt']?.toString();
    final b64 = map['b64_json']?.toString();
    if (b64 != null && b64.isNotEmpty) {
      out.add(
        ImageRef(
          type: ImageRefType.b64,
          src: b64.startsWith('data:')
              ? b64
              : 'data:image/png;base64,$b64',
          revisedPrompt: revised,
        ),
      );
      continue;
    }
    final url = map['url']?.toString();
    if (url != null && url.isNotEmpty) {
      out.add(
        ImageRef(
          type: ImageRefType.url,
          src: url,
          revisedPrompt: revised,
        ),
      );
    }
  }
  return out;
}
