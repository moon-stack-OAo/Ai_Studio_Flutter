import 'dart:async';
import 'dart:convert';

import 'mcp_client.dart';
import 'mcp_errors.dart';
import 'mcp_models.dart';
import 'mcp_sanitize.dart';
import 'process_host.dart';

/// MCP stdio 会话（DESIGN §5.11 · P6-S）。
///
/// 协议：每行一个 UTF-8 JSON-RPC message（newline delimited）。
/// 生命周期：经 [ProcessHost] 启动子进程 → `initialize` →
/// （可选）`notifications/initialized` → `tools/list` / `tools/call`；
/// [close] 必须 kill 子进程。
class StdioMcpSession implements McpSession {
  StdioMcpSession({
    required McpServerConfig server,
    required this.processHost,
    this.defaultCallTimeout = kDefaultMcpCallTimeout,
    this.protocolVersion = HttpSseMcpSession.kDefaultMcpProtocolVersion,
    this.clientName = 'ai-studio-flutter',
    this.clientVersion = '1.0.0',
  }) : _server = server {
    if (server.transport != McpTransport.stdio) {
      throw ArgumentError(
        'StdioMcpSession 仅支持 transport=stdio（当前 ${server.transport.wire}）',
      );
    }
    final cmd = server.command?.trim() ?? '';
    if (cmd.isEmpty) {
      throw ArgumentError('MCP stdio command 不能为空');
    }
  }

  final McpServerConfig _server;
  final ProcessHost processHost;
  final Duration defaultCallTimeout;
  final String protocolVersion;
  final String clientName;
  final String clientVersion;

  HostedProcess? _process;
  StreamSubscription<List<int>>? _stdoutSub;
  StreamSubscription<List<int>>? _stderrSub;
  StreamSubscription<int>? _exitSub;

  final _lineBuffer = StringBuffer();
  final _pending = <String, Completer<Map<String, dynamic>>>{};
  final _writeLock = _SerialLock();

  int _nextId = 1;
  bool _initialized = false;
  bool _closed = false;
  List<McpToolDescriptor>? _toolsCache;
  String? _serverName;
  String? _serverVersion;
  String? _lastStderrSnippet;

  @override
  McpServerConfig get server => _server;

  @override
  Future<McpProbeResult> probe({Duration? timeout}) async {
    final at = DateTime.now().millisecondsSinceEpoch;
    try {
      await _ensureStarted(timeout: timeout);
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
    await _ensureStarted(timeout: timeout);
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
      await _ensureStarted(timeout: timeout, isCancelled: isCancelled);
      await _ensureInitialized(timeout: timeout, isCancelled: isCancelled);
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
    _closed = true;
    _initialized = false;
    _toolsCache = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(const McpCancelledException('会话已关闭'));
      }
    }
    _pending.clear();
    unawaited(_stdoutSub?.cancel());
    unawaited(_stderrSub?.cancel());
    unawaited(_exitSub?.cancel());
    _stdoutSub = null;
    _stderrSub = null;
    _exitSub = null;
    final proc = _process;
    _process = null;
    if (proc != null) {
      try {
        proc.kill();
      } catch (_) {}
      try {
        proc.stdin.close();
      } catch (_) {}
    }
  }

  Future<void> _ensureStarted({
    Duration? timeout,
    bool Function()? isCancelled,
  }) async {
    if (_closed) {
      throw const McpCancelledException('会话已关闭');
    }
    if (_process != null) return;
    _throwIfCancelled(isCancelled);

    final cmd = _server.command!.trim();
    final args = List<String>.from(_server.args);
    final env = _server.env.isEmpty
        ? null
        : Map<String, String>.from(_server.env);
    final cwd = _server.cwd?.trim();
    final workingDirectory =
        (cwd == null || cwd.isEmpty) ? null : cwd;

    try {
      final started = processHost.start(
        command: cmd,
        arguments: args,
        environment: env,
        workingDirectory: workingDirectory,
      );
      _process = timeout == null
          ? await started
          : await started.timeout(timeout);
    } on TimeoutException {
      throw const McpTimeoutException('启动 MCP 子进程超时');
    } catch (e) {
      if (e is McpTimeoutException || e is McpCancelledException) rethrow;
      throw McpProcessException(
        mcpSanitizeSummary('无法启动 MCP 进程: $e', maxLen: 200),
      );
    }

    final proc = _process!;
    _stdoutSub = proc.stdout.listen(
      _onStdoutBytes,
      onError: (Object e, StackTrace st) {
        _failAllPending(McpProcessException(
          mcpSanitizeSummary('stdout 错误: $e', maxLen: 160),
        ));
      },
      onDone: () {
        _failAllPending(
          const McpProcessException('MCP 子进程 stdout 已关闭'),
        );
      },
      cancelOnError: false,
    );
    _stderrSub = proc.stderr.listen(
      (bytes) {
        final text = utf8.decode(bytes, allowMalformed: true);
        final trimmed = text.trim();
        if (trimmed.isEmpty) return;
        _lastStderrSnippet = mcpSanitizeSummary(trimmed, maxLen: 160);
      },
      onError: (_) {},
      cancelOnError: false,
    );
    _exitSub = proc.exitCode.asStream().listen((code) {
      final snippet = _lastStderrSnippet;
      final msg = snippet == null || snippet.isEmpty
          ? 'MCP 子进程已退出（code=$code）'
          : 'MCP 子进程已退出（code=$code）: $snippet';
      _failAllPending(McpProcessException(msg));
      _initialized = false;
    });
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
    bool requireInitialized = true,
  }) async {
    if (_closed) {
      throw const McpCancelledException('会话已关闭');
    }
    if (requireInitialized && !_initialized && method != 'initialize') {
      await _ensureInitialized(timeout: timeout, isCancelled: isCancelled);
    }
    _throwIfCancelled(isCancelled);
    await _ensureStarted(timeout: timeout, isCancelled: isCancelled);

    final id = _nextId++;
    final idKey = id.toString();
    final body = <String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': ?params,
    };

    final completer = Completer<Map<String, dynamic>>();
    _pending[idKey] = completer;

    try {
      await _writeLock.run(() async {
        _throwIfCancelled(isCancelled);
        final proc = _process;
        if (proc == null) {
          throw const McpProcessException('MCP 子进程未启动');
        }
        final line = '${jsonEncode(body)}\n';
        proc.stdin.add(utf8.encode(line));
        await proc.stdin.flush();
      });
    } catch (e) {
      _pending.remove(idKey);
      if (e is McpCancelledException ||
          e is McpTimeoutException ||
          e is McpProcessException ||
          e is McpProtocolException) {
        rethrow;
      }
      throw McpProcessException(
        mcpSanitizeSummary('写入 stdin 失败: $e', maxLen: 160),
      );
    }

    try {
      final result = await completer.future.timeout(timeout);
      _throwIfCancelled(isCancelled);
      return result;
    } on TimeoutException {
      _pending.remove(idKey);
      throw const McpTimeoutException();
    } catch (e) {
      _pending.remove(idKey);
      if (isMcpCancelLike(e) || isCancelled?.call() == true) {
        throw const McpCancelledException();
      }
      rethrow;
    }
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
    await _writeLock.run(() async {
      _throwIfCancelled(isCancelled);
      final proc = _process;
      if (proc == null) return;
      final line = '${jsonEncode(body)}\n';
      proc.stdin.add(utf8.encode(line));
      await proc.stdin.flush().timeout(timeout);
    });
  }

  void _onStdoutBytes(List<int> bytes) {
    _lineBuffer.write(utf8.decode(bytes, allowMalformed: true));
    var content = _lineBuffer.toString();
    var nl = content.indexOf('\n');
    while (nl >= 0) {
      var line = content.substring(0, nl);
      content = content.substring(nl + 1);
      if (line.endsWith('\r')) {
        line = line.substring(0, line.length - 1);
      }
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        _handleStdoutLine(trimmed);
      }
      nl = content.indexOf('\n');
    }
    _lineBuffer
      ..clear()
      ..write(content);
  }

  void _handleStdoutLine(String line) {
    late final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } catch (_) {
      _failAllPending(
        const McpProtocolException('stdout 行不是合法 JSON'),
      );
      return;
    }
    if (decoded is! Map) return;
    final map = Map<String, dynamic>.from(decoded);

    // 通知：无 id，忽略（或将来扩展）。
    if (!map.containsKey('id')) return;

    final idKey = map['id']?.toString() ?? '';
    final pending = _pending.remove(idKey);
    if (pending == null || pending.isCompleted) return;

    if (map.containsKey('error') && map['error'] != null) {
      pending.completeError(
        McpProtocolException(_formatRpcError(map['error'])),
      );
      return;
    }
    final result = map['result'];
    if (result is Map) {
      pending.complete(Map<String, dynamic>.from(result));
    } else if (result == null) {
      pending.completeError(
        const McpProtocolException('JSON-RPC 缺少 result'),
      );
    } else {
      pending.complete({'value': result});
    }
  }

  void _failAllPending(Object error) {
    final items = List<Completer<Map<String, dynamic>>>.from(_pending.values);
    _pending.clear();
    for (final c in items) {
      if (!c.isCompleted) c.completeError(error);
    }
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
    final structured =
        result['structuredContent'] ?? result['structured_content'];
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

  void _throwIfCancelled(bool Function()? isCancelled) {
    if (_closed || isCancelled?.call() == true) {
      throw const McpCancelledException();
    }
  }
}

/// 简单串行锁（保证 stdin 写入不交错）。
class _SerialLock {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final gate = Completer<void>();
    final prev = _tail;
    _tail = gate.future;
    return prev.then((_) => action()).whenComplete(gate.complete);
  }
}
