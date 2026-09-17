import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../chat/chat_errors.dart';
import '../chat/chat_models.dart';
import '../provider/provider_repository.dart';
import '../security/safe_http_client.dart';
import '../security/url_safety.dart';
import 'openai_urls.dart';
import 'sse_parser.dart';

/// 默认温度。
const double defaultChatTemperature = 0.7;

/// 默认连接/请求超时（约 180s）。
const Duration defaultChatTimeout = Duration(seconds: 180);

/// 流式对话累积结果（content 与可选 tool_calls）。
class ChatStreamResult {
  const ChatStreamResult({
    required this.content,
    this.toolCalls = const [],
    this.finishReason,
  });

  final String content;
  final List<ChatToolCall> toolCalls;
  final String? finishReason;

  bool get hasToolCalls => toolCalls.isNotEmpty;
}

/// OpenAI 兼容流式对话客户端。
class OpenAiCompatibleChatClient {
  OpenAiCompatibleChatClient({
    http.Client? client,
    this.timeout = defaultChatTimeout,
  })  : _ownedClient = client == null,
        _client = client ?? createSafeHttpClient();

  final http.Client _client;
  final bool _ownedClient;
  final Duration timeout;

  /// 是否由本实例创建 client（dispose 时关闭）。
  bool get ownsClient => _ownedClient;

  void close() {
    if (_ownedClient) {
      _client.close();
    }
  }

  /// 使用 [ActiveChatCredentials] 发起流式对话。
  Future<ChatStreamResult> streamChatWithCredentials(
    ActiveChatCredentials credentials, {
    required List<Map<String, dynamic>> messages,
    void Function(String delta, String fullText)? onDelta,
    double temperature = defaultChatTemperature,
    int? maxTokens,
    List<Map<String, dynamic>>? tools,
    Object? toolChoice,
    Duration? timeout,
    http.Client? client,
  }) {
    return streamChat(
      baseUrl: credentials.baseUrl,
      apiKey: credentials.apiKey,
      model: credentials.chatModel,
      messages: messages,
      onDelta: onDelta,
      temperature: temperature,
      maxTokens: maxTokens,
      tools: tools,
      toolChoice: toolChoice,
      timeout: timeout,
      client: client,
    );
  }

  /// 返回 [ChatStreamResult]；通过 [onDelta] 回调文本增量。
  ///
  /// [tools] / [toolChoice] 为可选；未传时请求体与历史行为一致（不带 tools）。
  /// 取消：传入可关闭的 [client] 并在外部 `client.close()`，
  /// 或使用本实例 [close]（仅当 ownsClient）。
  /// 用户取消抛出 [ChatAbortException]（文案「已取消」）。
  Future<ChatStreamResult> streamChat({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> messages,
    void Function(String delta, String fullText)? onDelta,
    double temperature = defaultChatTemperature,
    int? maxTokens,
    List<Map<String, dynamic>>? tools,
    Object? toolChoice,
    Duration? timeout,
    http.Client? client,
  }) async {
    final modelId = model.trim();
    if (modelId.isEmpty) {
      throw const ChatApiException('请先设置对话模型');
    }
    if (normalizeBaseUrl(baseUrl).isEmpty) {
      throw const ChatApiException('请先填写 Base URL');
    }
    try {
      assertSafeBaseUrl(baseUrl);
    } on UrlSafetyException catch (e) {
      throw ChatApiException(e.message);
    }

    final effectiveClient = client ?? _client;
    final reqTimeout = timeout ?? this.timeout;
    final body = <String, dynamic>{
      'model': modelId,
      'messages': messages,
      'stream': true,
      'temperature': temperature,
    };
    if (maxTokens != null && maxTokens > 0) {
      body['max_tokens'] = maxTokens;
    }
    if (tools != null && tools.isNotEmpty) {
      body['tools'] = tools;
      if (toolChoice != null) {
        body['tool_choice'] = toolChoice;
      }
    }

    final headers = authHeaders(
      apiKey,
      extra: {
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream, application/json',
      },
    );

    final request = http.Request('POST', chatCompletionsUri(baseUrl))
      ..headers.addAll(headers)
      ..body = jsonEncode(body);

    late http.StreamedResponse response;
    try {
      response = await effectiveClient.send(request).timeout(reqTimeout);
    } on TimeoutException {
      throw const ChatApiException('请求超时，请稍后重试或增大超时时间');
    } catch (e) {
      if (isAbortLike(e)) throw toAbortError();
      throw ChatApiException(describeNetworkError(e));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String raw = '';
      try {
        raw = await response.stream.bytesToString();
      } catch (_) {}
      String bodyMsg = '';
      try {
        final decoded = jsonDecode(raw);
        bodyMsg = extractApiErrorMessage(decoded);
      } catch (_) {
        bodyMsg = raw.trim();
        if (bodyMsg.length > 300) bodyMsg = bodyMsg.substring(0, 300);
      }
      final msg = httpStatusErrorMessage(response.statusCode, bodyMsg);
      final cleaned = sanitizeErrorText(msg, '');
      throw ChatApiException(
        cleaned.isNotEmpty ? cleaned : 'HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }

    final parser = SseLineParser();
    final toolAcc = ToolCallAccumulator();
    var fullText = '';
    String? finishReason;
    try {
      await for (final bytes in response.stream.timeout(reqTimeout)) {
        final chunk = utf8.decode(bytes, allowMalformed: true);
        final events = parser.addChunk(chunk);
        for (final event in events) {
          if (event.done) continue;
          if (event.finishReason != null) {
            finishReason = event.finishReason;
          }
          if (event.hasToolCallDeltas) {
            toolAcc.apply(event.toolCallDeltas);
          }
          if (event.delta.isEmpty) continue;
          fullText += event.delta;
          onDelta?.call(event.delta, fullText);
        }
      }
      for (final event in parser.flush()) {
        if (event.done) continue;
        if (event.finishReason != null) {
          finishReason = event.finishReason;
        }
        if (event.hasToolCallDeltas) {
          toolAcc.apply(event.toolCallDeltas);
        }
        if (event.delta.isEmpty) continue;
        fullText += event.delta;
        onDelta?.call(event.delta, fullText);
      }
    } on TimeoutException {
      throw const ChatApiException('请求超时，请稍后重试或增大超时时间');
    } on ChatApiException {
      rethrow;
    } on ChatAbortException {
      rethrow;
    } catch (e) {
      if (isAbortLike(e)) throw toAbortError();
      throw ChatApiException(describeNetworkError(e));
    }

    return ChatStreamResult(
      content: fullText,
      toolCalls: toolAcc.snapshot(),
      finishReason: finishReason,
    );
  }
}
