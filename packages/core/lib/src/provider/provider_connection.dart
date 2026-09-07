import 'dart:convert';

import 'package:http/http.dart' as http;

import '../security/url_safety.dart';
import 'provider_config.dart';

/// 连通性探测结果。
class ProviderConnectionResult {
  const ProviderConnectionResult({
    required this.ok,
    required this.detail,
    this.latencyMs,
    this.models = const [],
  });

  final bool ok;
  final String detail;
  final int? latencyMs;
  final List<ProviderModelInfo> models;
}

class ProviderModelInfo {
  const ProviderModelInfo({required this.id, this.ownedBy = ''});

  final String id;
  final String ownedBy;
}

/// 提供商连通性 / 拉模型钩子（B 阶段 SSE 可复用同一 HTTP 约定）。
abstract class ProviderConnectionTester {
  Future<ProviderConnectionResult> testConnection(ProviderConfig provider);

  Future<List<ProviderModelInfo>> listModels(ProviderConfig provider);
}

/// OpenAI 兼容实现：优先 GET `{baseUrl}/models`，失败且已配 chatModel 时回退最小 chat。
class OpenAiCompatibleConnectionTester implements ProviderConnectionTester {
  OpenAiCompatibleConnectionTester({
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  Uri _modelsUri(String baseUrl) {
    final trimmed = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$trimmed/models');
  }

  Uri _chatUri(String baseUrl) {
    final trimmed = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$trimmed/chat/completions');
  }

  Map<String, String> _headers(ProviderConfig provider) {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    final key = provider.apiKey.trim();
    if (key.isNotEmpty) {
      headers['Authorization'] = 'Bearer $key';
    }
    return headers;
  }

  String _describeHttpFailure(int? status, String raw) {
    if (status == 401 ||
        status == 403 ||
        RegExp(r'unauthorized|invalid.?api.?key|incorrect.?api',
                caseSensitive: false)
            .hasMatch(raw)) {
      return '鉴权失败（401/403），请检查 API Key';
    }
    if (status == 404 ||
        RegExp(r'\b404\b|not\s*found', caseSensitive: false).hasMatch(raw)) {
      return '接口不存在（404），请核对 Base URL 是否含 /v1 等路径';
    }
    if (status == 429 ||
        RegExp(r'rate.?limit|too many requests', caseSensitive: false)
            .hasMatch(raw)) {
      return '请求过于频繁（429），请稍后重试';
    }
    if (status != null && status >= 500) {
      return '上游服务异常（$status）';
    }
    final cleaned = raw.trim();
    if (cleaned.isNotEmpty) return cleaned;
    return '网络请求失败';
  }

  List<ProviderModelInfo> _parseModels(Object? decoded) {
    List<dynamic> list;
    if (decoded is Map && decoded['data'] is List) {
      list = decoded['data'] as List;
    } else if (decoded is List) {
      list = decoded;
    } else {
      list = const [];
    }
    final out = <ProviderModelInfo>[];
    for (final item in list) {
      if (item is String) {
        out.add(ProviderModelInfo(id: item));
        continue;
      }
      if (item is Map) {
        final id = item['id'] ?? item['name'];
        if (id == null) continue;
        out.add(ProviderModelInfo(
          id: id.toString(),
          ownedBy: item['owned_by']?.toString() ?? '',
        ));
      }
    }
    out.sort((a, b) => a.id.compareTo(b.id));
    return out;
  }

  @override
  Future<List<ProviderModelInfo>> listModels(ProviderConfig provider) async {
    if (provider.baseUrl.trim().isEmpty) {
      throw StateError('请先填写 Base URL');
    }
    try {
      assertSafeFetchUrl(provider.baseUrl.trim());
    } on UrlSafetyException catch (e) {
      throw StateError(e.message);
    }
    final response = await _client
        .get(_modelsUri(provider.baseUrl), headers: _headers(provider))
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        _describeHttpFailure(response.statusCode, response.body),
      );
    }
    final decoded = jsonDecode(response.body);
    return _parseModels(decoded);
  }

  @override
  Future<ProviderConnectionResult> testConnection(
    ProviderConfig provider,
  ) async {
    if (provider.baseUrl.trim().isEmpty) {
      return const ProviderConnectionResult(
        ok: false,
        detail: '请先填写 Base URL',
      );
    }
    try {
      assertSafeFetchUrl(provider.baseUrl.trim());
    } on UrlSafetyException catch (e) {
      return ProviderConnectionResult(ok: false, detail: e.message);
    }
    final sw = Stopwatch()..start();
    try {
      final models = await listModels(provider);
      sw.stop();
      return ProviderConnectionResult(
        ok: true,
        detail: '可达，模型列表约 ${models.length} 个',
        latencyMs: sw.elapsedMilliseconds,
        models: models,
      );
    } catch (modelsErr) {
      final chatModel = provider.chatModel.trim();
      if (chatModel.isEmpty) {
        return ProviderConnectionResult(
          ok: false,
          detail: modelsErr is StateError
              ? modelsErr.message
              : '模型列表不可达；未配置对话模型，无法回退探测 chat',
          latencyMs: sw.elapsedMilliseconds,
        );
      }
      try {
        final response = await _client
            .post(
              _chatUri(provider.baseUrl),
              headers: _headers(provider),
              body: jsonEncode({
                'model': chatModel,
                'messages': [
                  {'role': 'user', 'content': 'ping'},
                ],
                'max_tokens': 1,
                'stream': false,
              }),
            )
            .timeout(const Duration(seconds: 30));
        sw.stop();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final chatHint =
              _describeHttpFailure(response.statusCode, response.body);
          final modelsHint = modelsErr is StateError
              ? modelsErr.message
              : modelsErr.toString();
          return ProviderConnectionResult(
            ok: false,
            detail: '连接失败：$chatHint（模型列表：$modelsHint）',
            latencyMs: sw.elapsedMilliseconds,
          );
        }
        return ProviderConnectionResult(
          ok: true,
          detail: '对话接口可达（模型列表不可用，已用 chat 探测）',
          latencyMs: sw.elapsedMilliseconds,
        );
      } catch (chatErr) {
        sw.stop();
        final modelsHint =
            modelsErr is StateError ? modelsErr.message : modelsErr.toString();
        final chatHint =
            chatErr is StateError ? chatErr.message : chatErr.toString();
        return ProviderConnectionResult(
          ok: false,
          detail: '连接失败：$chatHint（模型列表：$modelsHint）',
          latencyMs: sw.elapsedMilliseconds,
        );
      }
    }
  }
}

/// 可注入的 stub（UI 联调 / 测试）。
class StubProviderConnectionTester implements ProviderConnectionTester {
  StubProviderConnectionTester({
    this.ok = true,
    this.detail = 'stub · 连接成功',
    this.models = const [
      ProviderModelInfo(id: 'gpt-4.1-mini'),
      ProviderModelInfo(id: 'gpt-image-1'),
      ProviderModelInfo(id: 'sora-2'),
    ],
  });

  final bool ok;
  final String detail;
  final List<ProviderModelInfo> models;

  @override
  Future<List<ProviderModelInfo>> listModels(ProviderConfig provider) async {
    if (!ok) throw StateError(detail);
    return models;
  }

  @override
  Future<ProviderConnectionResult> testConnection(
    ProviderConfig provider,
  ) async {
    return ProviderConnectionResult(
      ok: ok,
      detail: detail,
      latencyMs: 12,
      models: ok ? models : const [],
    );
  }
}
