import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../openai/sse_parser.dart';
import '../security/safe_http_client.dart';
import '../security/url_safety.dart';
import 'mcp_auth.dart';
import 'mcp_errors.dart';
import 'mcp_models.dart';
import 'mcp_sanitize.dart';
import 'process_host.dart';
import 'stdio_mcp_session.dart';

/// HTTP Client 工厂（默认 [createSafeHttpClient]）。
typedef McpHttpClientFactory = http.Client Function();

/// 出站 URL 校验钩子（默认 [assertSafeHttpUrl]）。
typedef McpUrlSafetyAssert = void Function(Uri url);

/// 单 Server 会话：探测 / listTools / callTool（DESIGN §5.11 · MCP-SESSION）。
///
/// 传输：HTTP/SSE（[HttpSseMcpSession]）或桌面 stdio（[StdioMcpSession]）。
abstract class McpSession {
  McpServerConfig get server;

  /// 健康探测（可顺带刷新 tools 缓存，由实现决定）。
  Future<McpProbeResult> probe({Duration? timeout});

  /// `tools/list`；成功时可写回调用方缓存。
  Future<List<McpToolDescriptor>> listTools({
    Duration? timeout,
    bool forceRefresh = false,
  });

  /// `tools/call`。
  ///
  /// [isCancelled] 为 true 时应中止并抛出 [McpCancelledException]。
  Future<McpToolCallResult> callTool(
    McpToolCallRequest request, {
    Duration? timeout,
    bool Function()? isCancelled,
  });

  void close();
}

/// 探测结果。
class McpProbeResult {
  const McpProbeResult({
    required this.ok,
    this.serverName,
    this.serverVersion,
    this.errorMessage,
    this.tools,
    this.atMs,
  });

  final bool ok;
  final String? serverName;
  final String? serverVersion;
  final String? errorMessage;
  final List<McpToolDescriptor>? tools;
  final int? atMs;

  factory McpProbeResult.failure(String message, {int? atMs}) =>
      McpProbeResult(
        ok: false,
        errorMessage: message,
        atMs: atMs ?? DateTime.now().millisecondsSinceEpoch,
      );
}

/// 创建 [McpSession] 的工厂（按 Server 配置）。
abstract class McpSessionFactory {
  /// [processHost]：stdio 传输需要；未注入时创建 stdio 会话将抛 [StateError]。
  McpSession create(
    McpServerConfig server, {
    McpAuthProvider? auth,
    ProcessHost? processHost,
  });
}

/// MCP Streamable HTTP 最小客户端（P6-2 首期）。
///
/// **Transport 假设（与业务 Server 联调约定）**：
/// - [McpServerConfig.baseUrl] 即为 MCP 单一入口（如 `https://host/mcp`），
///   对该 URL 发 **HTTP POST** JSON-RPC 2.0；
/// - 请求头：`Accept: application/json, text/event-stream`、
///   `Content-Type: application/json`、`MCP-Protocol-Version`；
///   若 Server 在 initialize 响应返回 `Mcp-Session-Id`，后续请求带回；
/// - 响应：`application/json` 单对象，或 `text/event-stream`（取末条含
///   匹配 `id` 的 JSON-RPC response）；
/// - 方法：`initialize` →（可选）`notifications/initialized` →
///   `tools/list` / `tools/call`；
/// - Auth：经 [McpAuthProvider] 附加 headers（none / bearer）。
///
/// 不做：OAuth、Resources/Prompts、完整双向 SSE 长连接、
/// `x-mcp-header` 参数镜像（业务 Server 勿依赖）。stdio 见 [StdioMcpSession]。
class HttpSseMcpSession implements McpSession {
  HttpSseMcpSession({
    required McpServerConfig server,
    required this.auth,
    McpHttpClientFactory? httpClientFactory,
    McpUrlSafetyAssert? assertUrl,
    this.defaultCallTimeout = kDefaultMcpCallTimeout,
    this.protocolVersion = kDefaultMcpProtocolVersion,
    this.clientName = 'ai-studio-flutter',
    this.clientVersion = '1.0.0',
  })  : _server = server,
        _httpClientFactory = httpClientFactory ?? createSafeHttpClient,
        _assertUrl = assertUrl ?? _defaultAssertUrl {
    final raw = server.baseUrl.trim();
    if (raw.isEmpty) {
      throw ArgumentError('MCP baseUrl 不能为空');
    }
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme) {
      throw ArgumentError('MCP baseUrl 无效');
    }
    try {
      _assertUrl(uri);
    } on UrlSafetyException catch (e) {
      throw McpUnsafeUrlException(e.message);
    }
    _endpoint = uri;
  }

  static void _defaultAssertUrl(Uri url) {
    assertSafeHttpUrl(url);
  }

  /// 首期协商的协议版本头（对齐 Streamable HTTP 常见值）。
  static const kDefaultMcpProtocolVersion = '2025-03-26';

  final McpServerConfig _server;
  late final Uri _endpoint;

  final McpAuthProvider auth;
  final McpHttpClientFactory _httpClientFactory;
  final McpUrlSafetyAssert _assertUrl;
  final Duration defaultCallTimeout;
  final String protocolVersion;
  final String clientName;
  final String clientVersion;

  http.Client? _client;
  int _nextId = 1;
  String? _sessionId;
  bool _initialized = false;
  List<McpToolDescriptor>? _toolsCache;
  String? _serverName;
  String? _serverVersion;

  @override
  McpServerConfig get server => _server;

  http.Client get client => _client ??= _httpClientFactory();

  Uri get endpoint => _endpoint;

  @override
  Future<McpProbeResult> probe({Duration? timeout}) async {
    final at = DateTime.now().millisecondsSinceEpoch;
    try {
      _throwIfCancelled(null);
      await _ensureInitialized(timeout: timeout);
      final tools = await listTools(timeout: timeout, forceRefresh: true);
      return McpProbeResult(
        ok: true,
        serverName: _serverName,
        serverVersion: _serverVersion,
        tools: tools,
        atMs: at,
      );
    } on McpCancelledException catch (e) {
      return McpProbeResult.failure(e.message, atMs: at);
    } catch (e) {
      return McpProbeResult.failure(
        mcpSanitizeSummary(e.toString(), maxLen: 240),
        atMs: at,
      );
    }
  }

  @override
  Future<List<McpToolDescriptor>> listTools({
    Duration? timeout,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _toolsCache != null) {
      return List.unmodifiable(_toolsCache!);
    }
    await _ensureInitialized(timeout: timeout);
    final result = await _rpc(
      'tools/list',
      params: const <String, dynamic>{},
      timeout: timeout ?? defaultCallTimeout,
    );
    final tools = _parseToolsList(result);
    _toolsCache = tools;
    return List.unmodifiable(tools);
  }

  @override
  Future<McpToolCallResult> callTool(
    McpToolCallRequest request, {
    Duration? timeout,
    bool Function()? isCancelled,
  }) async {
    final sw = Stopwatch()..start();
    try {
      _throwIfCancelled(isCancelled);
      await _ensureInitialized(
        timeout: timeout,
        isCancelled: isCancelled,
      );
      _throwIfCancelled(isCancelled);

      Map<String, dynamic> arguments;
      try {
        final decoded = jsonDecode(
          request.argumentsJson.trim().isEmpty
              ? '{}'
              : request.argumentsJson,
        );
        arguments = decoded is Map
            ? Map<String, dynamic>.from(decoded)
            : <String, dynamic>{};
      } catch (_) {
        arguments = <String, dynamic>{};
      }

      final result = await _rpc(
        'tools/call',
        params: {
          'name': request.toolName,
          'arguments': arguments,
        },
        timeout: timeout ?? defaultCallTimeout,
        isCancelled: isCancelled,
        mcpName: request.toolName,
      );

      final content = _extractToolContent(result);
      final isError = result['isError'] == true;
      return McpToolCallResult(
        toolCallId: request.toolCallId,
        status: isError ? McpToolCallStatus.failed : McpToolCallStatus.success,
        content: content,
        isError: isError,
        errorMessage: isError
            ? mcpSanitizeSummary(content, maxLen: 120)
            : null,
        latencyMs: sw.elapsedMilliseconds,
      );
    } on McpCancelledException {
      return McpToolCallResult(
        toolCallId: request.toolCallId,
        status: McpToolCallStatus.cancelled,
        content: '已取消',
        isError: true,
        errorMessage: 'cancelled',
        latencyMs: sw.elapsedMilliseconds,
      );
    } catch (e) {
      if (isMcpCancelLike(e) || isCancelled?.call() == true) {
        return McpToolCallResult(
          toolCallId: request.toolCallId,
          status: McpToolCallStatus.cancelled,
          content: '已取消',
          isError: true,
          errorMessage: 'cancelled',
          latencyMs: sw.elapsedMilliseconds,
        );
      }
      final msg = mcpSanitizeSummary(e.toString(), maxLen: 240);
      return McpToolCallResult(
        toolCallId: request.toolCallId,
        status: McpToolCallStatus.failed,
        content: msg.isEmpty ? '工具调用失败' : msg,
        isError: true,
        errorMessage: e.runtimeType.toString(),
        latencyMs: sw.elapsedMilliseconds,
      );
    }
  }

  @override
  void close() {
    _client?.close();
    _client = null;
    _initialized = false;
    _sessionId = null;
    _toolsCache = null;
  }

  Future<void> _ensureInitialized({
    Duration? timeout,
    bool Function()? isCancelled,
  }) async {
    if (_initialized) return;
    _throwIfCancelled(isCancelled);
    final result = await _rpc(
      'initialize',
      params: {
        'protocolVersion': protocolVersion,
        'capabilities': <String, dynamic>{},
        'clientInfo': {
          'name': clientName,
          'version': clientVersion,
        },
      },
      timeout: timeout ?? defaultCallTimeout,
      isCancelled: isCancelled,
      requireInitialized: false,
    );
    final info = result['serverInfo'];
    if (info is Map) {
      _serverName = info['name']?.toString();
      _serverVersion = info['version']?.toString();
    }
    _initialized = true;
    // 尽力发送 initialized 通知（失败不影响后续 tools）。
    try {
      await _rpcNotify(
        'notifications/initialized',
        timeout: timeout ?? defaultCallTimeout,
        isCancelled: isCancelled,
      );
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _rpc(
    String method, {
    Map<String, dynamic>? params,
    required Duration timeout,
    bool Function()? isCancelled,
    String? mcpName,
    bool requireInitialized = true,
  }) async {
    if (requireInitialized && !_initialized && method != 'initialize') {
      await _ensureInitialized(timeout: timeout, isCancelled: isCancelled);
    }
    _throwIfCancelled(isCancelled);
    try {
      _assertUrl(_endpoint);
    } on UrlSafetyException catch (e) {
      throw McpUnsafeUrlException(e.message);
    }

    final id = _nextId++;
    final body = <String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': ?params,
    };

    final headers = await _buildHeaders(
      method: method,
      mcpName: mcpName,
    );

    final request = http.Request('POST', _endpoint)
      ..headers.addAll(headers)
      ..body = jsonEncode(body);

    late http.StreamedResponse response;
    try {
      response = await client.send(request).timeout(timeout);
    } on TimeoutException {
      throw const McpTimeoutException();
    } catch (e) {
      if (isMcpCancelLike(e) || isCancelled?.call() == true) {
        throw const McpCancelledException();
      }
      throw McpHttpException(mcpSanitizeSummary(e.toString(), maxLen: 200));
    }

    _captureSessionId(response.headers);
    _throwIfCancelled(isCancelled);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String raw = '';
      try {
        raw = await response.stream.bytesToString().timeout(timeout);
      } catch (_) {}
      throw McpHttpException(
        _httpErrorMessage(response.statusCode, raw),
        statusCode: response.statusCode,
      );
    }

    final contentType =
        (response.headers['content-type'] ?? '').toLowerCase();
    if (contentType.contains('text/event-stream')) {
      return _readJsonRpcFromSse(
        response.stream,
        requestId: id,
        timeout: timeout,
        isCancelled: isCancelled,
      );
    }

    final raw = await response.stream.bytesToString().timeout(timeout);
    return _parseJsonRpcResponse(raw, expectedId: id);
  }

  Future<void> _rpcNotify(
    String method, {
    Map<String, dynamic>? params,
    required Duration timeout,
    bool Function()? isCancelled,
  }) async {
    _throwIfCancelled(isCancelled);
    final body = <String, dynamic>{
      'jsonrpc': '2.0',
      'method': method,
      'params': ?params,
    };
    final headers = await _buildHeaders(method: method);
    final request = http.Request('POST', _endpoint)
      ..headers.addAll(headers)
      ..body = jsonEncode(body);
    try {
      final response = await client.send(request).timeout(timeout);
      _captureSessionId(response.headers);
      // 202 / 2xx 均视为接受；读完流以免连接挂起。
      await response.stream.drain<void>().timeout(timeout);
    } on TimeoutException {
      // 通知失败忽略
    } catch (_) {}
  }

  Future<Map<String, String>> _buildHeaders({
    required String method,
    String? mcpName,
  }) async {
    final authHeaders = await auth.headers();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/event-stream',
      'MCP-Protocol-Version': protocolVersion,
      'Mcp-Method': method,
      ...authHeaders,
    };
    if (mcpName != null && mcpName.isNotEmpty) {
      headers['Mcp-Name'] = mcpName;
    }
    final sid = _sessionId;
    if (sid != null && sid.isNotEmpty) {
      headers['Mcp-Session-Id'] = sid;
    }
    return headers;
  }

  void _captureSessionId(Map<String, String> headers) {
    // http 包头名为小写。
    final sid = headers['mcp-session-id'] ?? headers['Mcp-Session-Id'];
    if (sid != null && sid.trim().isNotEmpty) {
      _sessionId = sid.trim();
    }
  }

  Future<Map<String, dynamic>> _readJsonRpcFromSse(
    Stream<List<int>> byteStream, {
    required int requestId,
    required Duration timeout,
    bool Function()? isCancelled,
  }) async {
    Map<String, dynamic>? lastResult;
    Object? lastError;
    var buffer = '';
    try {
      await for (final bytes in byteStream.timeout(timeout)) {
        _throwIfCancelled(isCancelled);
        buffer += utf8.decode(bytes, allowMalformed: true);
        final lines = buffer.split('\n');
        buffer = lines.removeLast();
        for (final line in lines) {
          final payload = extractSseDataPayload(line);
          if (payload == null || payload.isEmpty || payload == '[DONE]') {
            continue;
          }
          try {
            final decoded = jsonDecode(payload);
            if (decoded is! Map) continue;
            final map = Map<String, dynamic>.from(decoded);
            if (map['id'] != null &&
                map['id'].toString() != requestId.toString()) {
              continue;
            }
            if (map.containsKey('error') && map['error'] != null) {
              lastError = map['error'];
              continue;
            }
            if (map.containsKey('result')) {
              final r = map['result'];
              if (r is Map) {
                lastResult = Map<String, dynamic>.from(r);
              } else {
                lastResult = {'value': r};
              }
            }
          } catch (_) {}
        }
      }
      if (buffer.trim().isNotEmpty) {
        final payload = extractSseDataPayload(buffer);
        if (payload != null && payload.isNotEmpty && payload != '[DONE]') {
          try {
            final decoded = jsonDecode(payload);
            if (decoded is Map) {
              final map = Map<String, dynamic>.from(decoded);
              if (map['id'] == null ||
                  map['id'].toString() == requestId.toString()) {
                if (map.containsKey('error') && map['error'] != null) {
                  lastError = map['error'];
                } else if (map.containsKey('result')) {
                  final r = map['result'];
                  lastResult = r is Map
                      ? Map<String, dynamic>.from(r)
                      : {'value': r};
                }
              }
            }
          } catch (_) {}
        }
      }
    } on TimeoutException {
      throw const McpTimeoutException();
    } catch (e) {
      if (e is McpCancelledException) rethrow;
      if (isMcpCancelLike(e) || isCancelled?.call() == true) {
        throw const McpCancelledException();
      }
      rethrow;
    }
    if (lastError != null) {
      throw McpProtocolException(_formatRpcError(lastError));
    }
    final resolved = lastResult;
    if (resolved != null) return resolved;
    throw const McpProtocolException('SSE 响应缺少 JSON-RPC result');
  }

  Map<String, dynamic> _parseJsonRpcResponse(
    String raw, {
    required int expectedId,
  }) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const McpProtocolException('空响应');
    }
    late final Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (_) {
      throw const McpProtocolException('响应不是合法 JSON');
    }
    if (decoded is! Map) {
      throw const McpProtocolException('响应不是 JSON 对象');
    }
    final map = Map<String, dynamic>.from(decoded);
    if (map['id'] != null && map['id'] != expectedId) {
      // 宽松：部分 Server 用字符串 id。
      if (map['id'].toString() != expectedId.toString()) {
        throw McpProtocolException(
          'JSON-RPC id 不匹配（期望 $expectedId）',
        );
      }
    }
    if (map.containsKey('error') && map['error'] != null) {
      throw McpProtocolException(_formatRpcError(map['error']));
    }
    final result = map['result'];
    if (result is Map) return Map<String, dynamic>.from(result);
    if (result == null) {
      throw const McpProtocolException('JSON-RPC 缺少 result');
    }
    return {'value': result};
  }

  List<McpToolDescriptor> _parseToolsList(Map<String, dynamic> result) {
    final raw = result['tools'];
    if (raw is! List) return const [];
    final out = <McpToolDescriptor>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final map = Map<String, dynamic>.from(e);
      final name = map['name']?.toString().trim() ?? '';
      if (name.isEmpty) continue;
      final ann = map['annotations'];
      McpToolSideEffect side = McpToolSideEffect.unknown;
      McpToolPolicyLevel? suggested;
      if (ann is Map) {
        if (ann['readOnlyHint'] == true) {
          side = McpToolSideEffect.read;
          suggested = McpToolPolicyLevel.autoAllow;
        } else if (ann['destructiveHint'] == true) {
          side = McpToolSideEffect.write;
        }
        final se = ann['sideEffect']?.toString() ??
            map['sideEffect']?.toString();
        if (se != null) side = McpToolSideEffect.tryParse(se);
      } else if (map['sideEffect'] != null) {
        side = McpToolSideEffect.tryParse(map['sideEffect']?.toString());
      }
      String? schemaSummary;
      final schema = map['inputSchema'] ?? map['input_schema'];
      if (schema is Map) {
        try {
          schemaSummary = jsonEncode(schema);
        } catch (_) {
          schemaSummary = schema.toString();
        }
      }
      out.add(
        McpToolDescriptor(
          name: name,
          title: map['title']?.toString(),
          description: map['description']?.toString(),
          sideEffect: side,
          inputSchemaSummary: schemaSummary,
          suggestedPolicy: suggested,
        ),
      );
    }
    return out;
  }

  String _extractToolContent(Map<String, dynamic> result) {
    final content = result['content'];
    if (content is List) {
      final parts = <String>[];
      for (final block in content) {
        if (block is Map) {
          final type = block['type']?.toString();
          if (type == 'text' || block['text'] != null) {
            final t = block['text']?.toString() ?? '';
            if (t.isNotEmpty) parts.add(t);
          } else {
            try {
              parts.add(jsonEncode(block));
            } catch (_) {
              parts.add(block.toString());
            }
          }
        } else if (block != null) {
          parts.add(block.toString());
        }
      }
      if (parts.isNotEmpty) return parts.join('\n');
    }
    if (content is String) return content;
    final structured = result['structuredContent'] ?? result['structured_content'];
    if (structured != null) {
      try {
        return jsonEncode(structured);
      } catch (_) {
        return structured.toString();
      }
    }
    try {
      return jsonEncode(result);
    } catch (_) {
      return result.toString();
    }
  }

  String _formatRpcError(Object? error) {
    if (error is Map) {
      final msg = error['message']?.toString();
      final code = error['code'];
      if (msg != null && msg.isNotEmpty) {
        return code != null ? '[$code] $msg' : msg;
      }
    }
    return mcpSanitizeSummary(error?.toString() ?? '协议错误', maxLen: 200);
  }

  String _httpErrorMessage(int status, String raw) {
    var body = raw.trim();
    if (body.length > 200) body = '${body.substring(0, 200)}…';
    body = mcpSanitizeSummary(body, maxLen: 200);
    if (body.isEmpty) return 'HTTP $status';
    return 'HTTP $status: $body';
  }

  void _throwIfCancelled(bool Function()? isCancelled) {
    if (isCancelled?.call() == true) {
      throw const McpCancelledException();
    }
  }
}

/// 默认工厂：按 [McpServerConfig.transport] 产出 HTTP 或 stdio 会话。
///
/// 桌面应注入 [processHost]（可用 [IoProcessHost]）；mobile 不注入，
/// 遇 `transport=stdio` 时抛 [StateError]。
class HttpSseMcpSessionFactory implements McpSessionFactory {
  HttpSseMcpSessionFactory({
    required this.secretStoreAuthBuilder,
    this.httpClientFactory,
    this.assertUrl,
    this.processHost,
  });

  /// 由 Server 配置构建 [McpAuthProvider]（通常包一层 [createMcpAuthProvider]）。
  final McpAuthProvider Function(McpServerConfig server) secretStoreAuthBuilder;
  final McpHttpClientFactory? httpClientFactory;
  final McpUrlSafetyAssert? assertUrl;

  /// 桌面注入的进程宿主；stdio 会话必需。
  final ProcessHost? processHost;

  @override
  McpSession create(
    McpServerConfig server, {
    McpAuthProvider? auth,
    ProcessHost? processHost,
  }) {
    final host = processHost ?? this.processHost;
    switch (server.transport) {
      case McpTransport.http:
        return HttpSseMcpSession(
          server: server,
          auth: auth ?? secretStoreAuthBuilder(server),
          httpClientFactory: httpClientFactory,
          assertUrl: assertUrl,
        );
      case McpTransport.stdio:
        if (host == null) {
          throw StateError(
            'stdio MCP 需要 ProcessHost（桌面未注入；移动端不支持本地子进程）',
          );
        }
        return StdioMcpSession(
          server: server,
          processHost: host,
        );
    }
  }
}
