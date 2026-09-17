import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const server = McpServerConfig(
    id: 'mcp_t',
    displayName: 'Test',
    baseUrl: 'https://mcp.example.local/mcp',
  );

  group('HttpSseMcpSession', () {
    test('initialize + tools/list (JSON)', () async {
      final calls = <String>[];
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.toString(), 'https://mcp.example.local/mcp');
        expect(
          request.headers['accept'],
          contains('application/json'),
        );
        expect(request.headers['mcp-protocol-version'], isNotNull);
        final body = jsonDecode(request.body) as Map;
        final method = body['method'] as String;
        calls.add(method);
        final id = body['id'];

        if (method == 'initialize') {
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'result': {
                'protocolVersion': '2025-03-26',
                'capabilities': {'tools': {}},
                'serverInfo': {'name': 'biz', 'version': '1.0'},
              },
            }),
            200,
            headers: {
              'content-type': 'application/json',
              'mcp-session-id': 'sess-1',
            },
          );
        }
        if (method == 'notifications/initialized') {
          return http.Response('', 202);
        }
        if (method == 'tools/list') {
          expect(request.headers['mcp-session-id'], 'sess-1');
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'result': {
                'tools': [
                  {
                    'name': 'biz.query',
                    'title': '查询',
                    'description': '查数据',
                    'inputSchema': {
                      'type': 'object',
                      'properties': {
                        'q': {'type': 'string'},
                      },
                    },
                    'annotations': {'readOnlyHint': true},
                  },
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        fail('unexpected method $method');
      });

      final session = HttpSseMcpSession(
        server: server,
        auth: const NoneMcpAuth(),
        httpClientFactory: () => client,
      );
      final tools = await session.listTools();
      expect(tools, hasLength(1));
      expect(tools.single.name, 'biz.query');
      expect(tools.single.sideEffect, McpToolSideEffect.read);
      expect(calls, contains('initialize'));
      expect(calls, contains('tools/list'));
      session.close();
    });

    test('tools/call with Bearer auth', () async {
      final store = MemorySecretStore({'ref': 'secret-tok'});
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        final method = body['method'] as String;
        final id = body['id'];
        if (method == 'initialize') {
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'result': {
                'protocolVersion': '2025-03-26',
                'capabilities': {},
                'serverInfo': {'name': 's', 'version': '0'},
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (method == 'notifications/initialized') {
          return http.Response('', 202);
        }
        if (method == 'tools/call') {
          expect(request.headers['authorization'], 'Bearer secret-tok');
          expect(request.headers['mcp-name'], 'biz.query');
          final params = body['params'] as Map;
          expect(params['name'], 'biz.query');
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'result': {
                'content': [
                  {'type': 'text', 'text': 'ok-result'},
                ],
                'isError': false,
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        fail('unexpected $method');
      });

      final session = HttpSseMcpSession(
        server: server.copyWith(
          authKind: McpAuthKind.bearer,
          authSecretRef: 'ref',
        ),
        auth: BearerMcpAuth(secretStore: store, secretRef: 'ref'),
        httpClientFactory: () => client,
      );
      final result = await session.callTool(
        const McpToolCallRequest(
          toolCallId: 'call_1',
          serverId: 'mcp_t',
          toolName: 'biz.query',
          argumentsJson: '{"q":"x"}',
        ),
      );
      expect(result.isSuccess, isTrue);
      expect(result.content, 'ok-result');
      session.close();
    });

    test('SSE tools/list response', () async {
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        final method = body['method'] as String;
        final id = body['id'];
        if (method == 'initialize') {
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'result': {
                'protocolVersion': '2025-03-26',
                'capabilities': {},
                'serverInfo': {'name': 's', 'version': '0'},
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (method == 'notifications/initialized') {
          return http.Response('', 202);
        }
        if (method == 'tools/list') {
          final sse = 'data: {"jsonrpc":"2.0","id":$id,"result":{"tools":[{"name":"t1"}]}}\n\n';
          return http.Response(
            sse,
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }
        fail('unexpected $method');
      });

      final session = HttpSseMcpSession(
        server: server,
        auth: const NoneMcpAuth(),
        httpClientFactory: () => client,
      );
      final tools = await session.listTools();
      expect(tools.single.name, 't1');
      session.close();
    });

    test('unsafe URL rejected at construct', () {
      expect(
        () => HttpSseMcpSession(
          server: const McpServerConfig(
            id: 'x',
            displayName: 'x',
            baseUrl: 'https://169.254.169.254/mcp',
          ),
          auth: const NoneMcpAuth(),
        ),
        throwsA(isA<McpUnsafeUrlException>()),
      );
    });

    test('cancel during call', () async {
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        final method = body['method'] as String;
        final id = body['id'];
        if (method == 'initialize') {
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'result': {
                'protocolVersion': '2025-03-26',
                'capabilities': {},
                'serverInfo': {'name': 's', 'version': '0'},
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (method == 'notifications/initialized') {
          return http.Response('', 202);
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return http.Response('{}', 200);
      });

      final session = HttpSseMcpSession(
        server: server,
        auth: const NoneMcpAuth(),
        httpClientFactory: () => client,
      );
      var cancelled = false;
      final future = session.callTool(
        const McpToolCallRequest(
          toolCallId: 'c',
          serverId: 'mcp_t',
          toolName: 't',
        ),
        isCancelled: () => cancelled,
      );
      cancelled = true;
      final result = await future;
      expect(result.status, McpToolCallStatus.cancelled);
      session.close();
    });

    test('probe aggregates listTools', () async {
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        final method = body['method'] as String;
        final id = body['id'];
        if (method == 'initialize') {
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'result': {
                'protocolVersion': '2025-03-26',
                'capabilities': {},
                'serverInfo': {'name': 'biz', 'version': '2'},
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (method == 'notifications/initialized') {
          return http.Response('', 202);
        }
        if (method == 'tools/list') {
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'result': {
                'tools': [
                  {'name': 'a'},
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        fail(method);
      });
      final session = HttpSseMcpSession(
        server: server,
        auth: const NoneMcpAuth(),
        httpClientFactory: () => client,
      );
      final probe = await session.probe();
      expect(probe.ok, isTrue);
      expect(probe.serverName, 'biz');
      expect(probe.tools!.single.name, 'a');
      session.close();
    });
  });

  group('mcpSanitizeSummary', () {
    test('redacts bearer and truncates', () {
      final s = mcpSanitizeSummary(
        'Authorization: Bearer sk-abcdefghijklmnop ${'x' * 300}',
      );
      expect(s, isNot(contains('sk-abcdefghijklmnop')));
      expect(s.length, lessThanOrEqualTo(kMcpSummaryMaxLen + 1));
    });

    test('mcpArgumentsSummary redacts token-like fields', () {
      final s = mcpArgumentsSummary(
        '{"api_key":"sk-secretvalue123","phone":"13800138000"}',
      );
      expect(s, isNot(contains('sk-secretvalue123')));
      expect(s, contains('***'));
    });
  });
}
