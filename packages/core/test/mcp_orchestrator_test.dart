import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSession implements McpSession {
  _FakeSession(this.server);

  @override
  final McpServerConfig server;

  final calls = <McpToolCallRequest>[];

  @override
  Future<McpProbeResult> probe({Duration? timeout}) async =>
      const McpProbeResult(ok: true);

  @override
  Future<List<McpToolDescriptor>> listTools({
    Duration? timeout,
    bool forceRefresh = false,
  }) async =>
      server.toolsCache;

  @override
  Future<McpToolCallResult> callTool(
    McpToolCallRequest request, {
    Duration? timeout,
    bool Function()? isCancelled,
  }) async {
    calls.add(request);
    return McpToolCallResult(
      toolCallId: request.toolCallId,
      status: McpToolCallStatus.success,
      content: 'ok:${request.toolName}',
    );
  }

  @override
  void close() {}
}

void main() {
  const server = McpServerConfig(
    id: 's1',
    displayName: 'S1',
    baseUrl: 'https://mcp.example.local/mcp',
    toolsCache: [
      McpToolDescriptor(
        name: 'read.t',
        sideEffect: McpToolSideEffect.read,
      ),
      McpToolDescriptor(
        name: 'write.t',
        sideEffect: McpToolSideEffect.write,
      ),
    ],
  );

  test('serial: deny does not call; autoAllow calls; confirm uses prompter',
      () async {
    final session = _FakeSession(server);
    final orch = DefaultToolCallOrchestrator(
      resolveSession: (_) => session,
      resolveServer: (_) => server,
      resolveTool: (_, name) =>
          server.toolsCache.firstWhere((t) => t.name == name),
    );

    final prompts = <String>[];
    final results = await orch.runRound(
      calls: const [
        McpToolCallRequest(
          toolCallId: '1',
          serverId: 's1',
          toolName: 'write.t',
          argumentsJson: '{}',
        ),
        McpToolCallRequest(
          toolCallId: '2',
          serverId: 's1',
          toolName: 'read.t',
          argumentsJson: '{}',
        ),
      ],
      prompter: (p) async {
        prompts.add(p.toolName);
        return p.toolName == 'write.t';
      },
    );

    expect(prompts, ['write.t']);
    expect(session.calls.map((c) => c.toolName), ['write.t', 'read.t']);
    expect(results[0].isSuccess, isTrue);
    expect(results[1].isSuccess, isTrue);
  });

  test('user reject → no callTool', () async {
    final session = _FakeSession(server);
    final orch = DefaultToolCallOrchestrator(
      resolveSession: (_) => session,
      resolveServer: (_) => server,
      resolveTool: (_, name) =>
          server.toolsCache.firstWhere((t) => t.name == name),
    );
    final results = await orch.runRound(
      calls: const [
        McpToolCallRequest(
          toolCallId: '1',
          serverId: 's1',
          toolName: 'write.t',
        ),
      ],
      prompter: denyAllToolAuthPrompter,
    );
    expect(session.calls, isEmpty);
    expect(results.single.status, McpToolCallStatus.rejected);
    expect(results.single.errorMessage, 'user_rejected');
  });

  test('policy deny → no call', () async {
    final denied = server.copyWith(
      toolPolicyOverrides: {'write.t': McpToolPolicyLevel.deny},
    );
    final session = _FakeSession(denied);
    final orch = DefaultToolCallOrchestrator(
      resolveSession: (_) => session,
      resolveServer: (_) => denied,
      resolveTool: (_, name) =>
          denied.toolsCache.firstWhere((t) => t.name == name),
    );
    final results = await orch.runRound(
      calls: const [
        McpToolCallRequest(
          toolCallId: '1',
          serverId: 's1',
          toolName: 'write.t',
        ),
      ],
      prompter: allowAllToolAuthPrompter,
    );
    expect(session.calls, isEmpty);
    expect(results.single.errorMessage, 'policy_deny');
  });

  test('empty serverId → unknown_tool', () async {
    final session = _FakeSession(server);
    final orch = DefaultToolCallOrchestrator(
      resolveSession: (_) => session,
      resolveServer: (_) => server,
      resolveTool: (_, name) => McpToolDescriptor(name: name),
    );
    final results = await orch.runRound(
      calls: const [
        McpToolCallRequest(
          toolCallId: '1',
          serverId: '',
          toolName: 'ghost',
        ),
      ],
      prompter: allowAllToolAuthPrompter,
    );
    expect(session.calls, isEmpty);
    expect(results.single.errorMessage, 'unknown_tool');
  });
}
