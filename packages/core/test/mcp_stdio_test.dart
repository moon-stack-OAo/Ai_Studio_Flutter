import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

/// 脚本式 Fake：按收到的 JSON-RPC method 应答（newline delimited）。
class _ScriptedProcessHost implements ProcessHost {
  _ScriptedProcessHost(this.handler);

  final Map<String, dynamic> Function(Map<String, dynamic> request) handler;

  _FakeHostedProcess? lastProcess;
  var startCount = 0;

  @override
  Future<HostedProcess> start({
    required String command,
    List<String> arguments = const [],
    Map<String, String>? environment,
    String? workingDirectory,
  }) async {
    startCount++;
    final proc = _FakeHostedProcess(handler);
    lastProcess = proc;
    return proc;
  }
}

class _FakeHostedProcess implements HostedProcess {
  _FakeHostedProcess(this._handler) {
    _stdinController.stream.listen((bytes) {
      _stdinBuffer.write(utf8.decode(bytes));
      var content = _stdinBuffer.toString();
      var nl = content.indexOf('\n');
      while (nl >= 0) {
        final line = content.substring(0, nl).trim();
        content = content.substring(nl + 1);
        if (line.isNotEmpty) _onStdinLine(line);
        nl = content.indexOf('\n');
      }
      _stdinBuffer
        ..clear()
        ..write(content);
    });
  }

  final Map<String, dynamic> Function(Map<String, dynamic> request) _handler;
  final _stdinBuffer = StringBuffer();
  final _stdinController = StreamController<List<int>>();
  final _stdoutController = StreamController<List<int>>.broadcast();
  final _stderrController = StreamController<List<int>>.broadcast();
  final _exit = Completer<int>();
  var _running = true;
  late final IOSink _stdinSink = _FakeIoSink(_stdinController);

  @override
  IOSink get stdin => _stdinSink;

  @override
  Stream<List<int>> get stdout => _stdoutController.stream;

  @override
  Stream<List<int>> get stderr => _stderrController.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  bool get isRunning => _running;

  @override
  bool kill() {
    _running = false;
    if (!_exit.isCompleted) _exit.complete(0);
    unawaited(_stdinController.close());
    unawaited(_stdoutController.close());
    unawaited(_stderrController.close());
    return true;
  }

  void _onStdinLine(String line) {
    final decoded = jsonDecode(line);
    if (decoded is! Map) return;
    final req = Map<String, dynamic>.from(decoded);
    // 通知无 id：不写响应。
    if (!req.containsKey('id')) return;
    final response = _handler(req);
    final out = Map<String, dynamic>.from(response);
    out.putIfAbsent('jsonrpc', () => '2.0');
    out.putIfAbsent('id', () => req['id']);
    _stdoutController.add(utf8.encode('${jsonEncode(out)}\n'));
  }
}

/// 最小 IOSink：只转发 add/flush/close。
class _FakeIoSink implements IOSink {
  _FakeIoSink(this._controller);

  final StreamController<List<int>> _controller;

  @override
  Encoding encoding = utf8;

  @override
  void add(List<int> data) => _controller.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _controller.addError(error, stackTrace);

  @override
  Future<dynamic> addStream(Stream<List<int>> stream) =>
      stream.listen(add).asFuture<void>();

  @override
  Future<void> close() async {
    await _controller.close();
  }

  @override
  Future<void> get done => _controller.done;

  @override
  Future<void> flush() async {}

  @override
  void write(Object? object) => add(utf8.encode('$object'));

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) =>
      write(objects.join(separator));

  @override
  void writeCharCode(int charCode) => add([charCode]);

  @override
  void writeln([Object? object = '']) => write('$object\n');
}

void main() {
  group('McpTransport / McpServerConfig stdio fields', () {
    test('json round-trip preserves transport/command/args/env/cwd', () {
      const original = McpServerConfig(
        id: 'mcp_stdio',
        displayName: 'Local',
        transport: McpTransport.stdio,
        command: 'node',
        args: ['server.js', '--port', '0'],
        env: {'API_KEY': 'secret-env', 'DEBUG': '1'},
        cwd: '/tmp/mcp',
        enabled: true,
      );
      final meta = original.toJsonMeta();
      expect(meta['transport'], 'stdio');
      expect(meta['command'], 'node');
      expect(meta['args'], ['server.js', '--port', '0']);
      expect(meta['env'], {'API_KEY': 'secret-env', 'DEBUG': '1'});
      expect(meta['cwd'], '/tmp/mcp');

      final restored = McpServerConfig.fromJson(meta);
      expect(restored.transport, McpTransport.stdio);
      expect(restored.command, 'node');
      expect(restored.args, original.args);
      expect(restored.env, original.env);
      expect(restored.cwd, '/tmp/mcp');
      expect(restored.canExposeTools, isTrue);
    });

    test('legacy json without transport defaults to http', () {
      final s = McpServerConfig.fromJson({
        'id': 'old',
        'displayName': 'Old',
        'baseUrl': 'https://mcp.example/mcp',
      });
      expect(s.transport, McpTransport.http);
      expect(s.canExposeTools, isTrue);
    });

    test('canExposeTools: http needs url; stdio needs command', () {
      const httpOk = McpServerConfig(
        id: 'h',
        displayName: 'H',
        baseUrl: 'https://x/mcp',
      );
      const httpNoUrl = McpServerConfig(
        id: 'h2',
        displayName: 'H2',
      );
      const stdioOk = McpServerConfig(
        id: 's',
        displayName: 'S',
        transport: McpTransport.stdio,
        command: 'npx',
        args: ['-y', 'demo'],
      );
      const stdioNoCmd = McpServerConfig(
        id: 's2',
        displayName: 'S2',
        transport: McpTransport.stdio,
      );
      expect(httpOk.canExposeTools, isTrue);
      expect(httpNoUrl.canExposeTools, isFalse);
      expect(stdioOk.canExposeTools, isTrue);
      expect(stdioNoCmd.canExposeTools, isFalse);
      expect(stdioOk.copyWith(enabled: false).canExposeTools, isFalse);
    });

    test('toJsonForBackup omits env when includeSecrets=false', () {
      const s = McpServerConfig(
        id: 'mcp_s',
        displayName: 'S',
        transport: McpTransport.stdio,
        command: 'node',
        args: ['a.js'],
        env: {'TOKEN': 'abc'},
        cwd: '/w',
      );
      final scrubbed = s.toJsonForBackup(includeSecrets: false);
      expect(scrubbed.containsKey('env'), isFalse);
      expect(scrubbed['command'], 'node');
      expect(scrubbed['args'], ['a.js']);
      expect(scrubbed['cwd'], '/w');

      final full = s.toJsonForBackup(includeSecrets: true);
      expect(full['env'], {'TOKEN': 'abc'});
    });

    test('McpTransport.tryParse aliases', () {
      expect(McpTransport.tryParse('stdio'), McpTransport.stdio);
      expect(McpTransport.tryParse('local'), McpTransport.stdio);
      expect(McpTransport.tryParse('http'), McpTransport.http);
      expect(McpTransport.tryParse('SSE'), McpTransport.http);
      expect(McpTransport.tryParse('nope'), isNull);
    });
  });

  group('mergeMcpServers copies stdio fields', () {
    test('merge overlays transport/command/args/env/cwd', () {
      const local = McpServerConfig(
        id: 'mcp_1',
        displayName: 'Old',
        transport: McpTransport.http,
        baseUrl: 'https://old/mcp',
      );
      final incoming = [
        DataBackupMcpServer(
          config: const McpServerConfig(
            id: 'mcp_1',
            displayName: 'New',
            transport: McpTransport.stdio,
            command: 'node',
            args: ['srv.js'],
            env: {'K': 'V'},
            cwd: '/home/mcp',
          ),
        ),
      ];
      final merge = mergeMcpServers(
        local: [local],
        incoming: incoming,
        applySecrets: false,
      );
      expect(merge.mergedCount, 1);
      final s = merge.servers.single;
      expect(s.transport, McpTransport.stdio);
      expect(s.command, 'node');
      expect(s.args, ['srv.js']);
      expect(s.env, {'K': 'V'});
      expect(s.cwd, '/home/mcp');
      expect(s.displayName, 'New');
    });
  });

  group('policy unaffected by transport', () {
    test('resolver still works for stdio server', () {
      const resolver = McpToolPolicyResolver();
      const server = McpServerConfig(
        id: 'mcp_stdio',
        displayName: 'Local',
        transport: McpTransport.stdio,
        command: 'node',
        defaultToolPolicy: McpToolPolicyLevel.autoAllow,
      );
      const tool = McpToolDescriptor(
        name: 'biz.query',
        sideEffect: McpToolSideEffect.write,
      );
      expect(
        resolver.resolve(server: server, tool: tool),
        McpToolPolicyLevel.autoAllow,
      );
    });
  });

  group('HttpSseMcpSessionFactory transport routing', () {
    test('stdio without ProcessHost throws StateError', () {
      final factory = HttpSseMcpSessionFactory(
        secretStoreAuthBuilder: (_) => const NoneMcpAuth(),
      );
      expect(
        () => factory.create(
          const McpServerConfig(
            id: 's',
            displayName: 'S',
            transport: McpTransport.stdio,
            command: 'node',
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('stdio with ProcessHost yields StdioMcpSession', () {
      final host = _ScriptedProcessHost((_) => {'result': {}});
      final factory = HttpSseMcpSessionFactory(
        secretStoreAuthBuilder: (_) => const NoneMcpAuth(),
        processHost: host,
      );
      final session = factory.create(
        const McpServerConfig(
          id: 's',
          displayName: 'S',
          transport: McpTransport.stdio,
          command: 'node',
          args: ['x.js'],
        ),
      );
      expect(session, isA<StdioMcpSession>());
      session.close();
    });
  });

  group('StdioMcpSession with Fake ProcessHost', () {
    late _ScriptedProcessHost host;

    setUp(() {
      host = _ScriptedProcessHost((req) {
        final method = req['method']?.toString() ?? '';
        final id = req['id'];
        if (method == 'initialize') {
          return {
            'id': id,
            'result': {
              'protocolVersion': '2025-03-26',
              'capabilities': {'tools': {}},
              'serverInfo': {'name': 'fake-stdio', 'version': '0.1'},
            },
          };
        }
        if (method == 'tools/list') {
          return {
            'id': id,
            'result': {
              'tools': [
                {
                  'name': 'biz.query',
                  'title': '查询',
                  'annotations': {'readOnlyHint': true},
                },
              ],
            },
          };
        }
        if (method == 'tools/call') {
          final params = req['params'] as Map? ?? {};
          return {
            'id': id,
            'result': {
              'content': [
                {'type': 'text', 'text': 'called:${params['name']}'},
              ],
              'isError': false,
            },
          };
        }
        fail('unexpected method $method');
      });
    });

    test('probe + listTools succeed', () async {
      const server = McpServerConfig(
        id: 'mcp_local',
        displayName: 'Local',
        transport: McpTransport.stdio,
        command: 'node',
        args: ['mcp-server.js'],
        env: {'FOO': 'bar'},
        cwd: '/tmp',
      );
      final session = StdioMcpSession(server: server, processHost: host);
      final probe = await session.probe();
      expect(probe.ok, isTrue);
      expect(probe.serverName, 'fake-stdio');
      expect(probe.tools, isNotNull);
      expect(probe.tools!.single.name, 'biz.query');
      expect(host.startCount, 1);

      final tools = await session.listTools();
      expect(tools.single.sideEffect, McpToolSideEffect.read);
      session.close();
      expect(host.lastProcess?.isRunning, isFalse);
    });

    test('callTool returns content', () async {
      const server = McpServerConfig(
        id: 'mcp_local',
        displayName: 'Local',
        transport: McpTransport.stdio,
        command: 'node',
      );
      final session = StdioMcpSession(server: server, processHost: host);
      final result = await session.callTool(
        const McpToolCallRequest(
          toolCallId: 'tc1',
          serverId: 'mcp_local',
          toolName: 'biz.query',
          argumentsJson: '{"q":"x"}',
        ),
      );
      expect(result.isSuccess, isTrue);
      expect(result.content, 'called:biz.query');
      session.close();
    });

    test('close kills process', () async {
      const server = McpServerConfig(
        id: 'mcp_local',
        displayName: 'Local',
        transport: McpTransport.stdio,
        command: 'node',
      );
      final session = StdioMcpSession(server: server, processHost: host);
      await session.listTools();
      expect(host.lastProcess?.isRunning, isTrue);
      session.close();
      expect(host.lastProcess?.isRunning, isFalse);
    });
  });
}
