import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const resolver = McpToolPolicyResolver();
  const server = McpServerConfig(
    id: 'mcp_1',
    displayName: 'Biz',
    baseUrl: 'https://mcp.example.local',
  );

  group('McpToolPolicyResolver', () {
    test('default: read → autoAllow, write/unknown → confirmAlways', () {
      expect(
        McpToolPolicyResolver.defaultLevelFor(McpToolSideEffect.read),
        McpToolPolicyLevel.autoAllow,
      );
      expect(
        McpToolPolicyResolver.defaultLevelFor(McpToolSideEffect.write),
        McpToolPolicyLevel.confirmAlways,
      );
      expect(
        McpToolPolicyResolver.defaultLevelFor(McpToolSideEffect.unknown),
        McpToolPolicyLevel.confirmAlways,
      );
    });

    test('user override wins over suggested and default', () {
      const tool = McpToolDescriptor(
        name: 'biz.query',
        sideEffect: McpToolSideEffect.read,
        suggestedPolicy: McpToolPolicyLevel.autoAllow,
      );
      final level = resolver.resolve(
        server: server.copyWith(
          toolPolicyOverrides: {
            'biz.query': McpToolPolicyLevel.deny,
          },
        ),
        tool: tool,
      );
      expect(level, McpToolPolicyLevel.deny);
    });

    test('suggestedPolicy used when no user override', () {
      const tool = McpToolDescriptor(
        name: 'biz.write',
        sideEffect: McpToolSideEffect.write,
        suggestedPolicy: McpToolPolicyLevel.confirmOnce,
      );
      expect(
        resolver.resolve(server: server, tool: tool),
        McpToolPolicyLevel.confirmOnce,
      );
    });

    test('server defaultToolPolicy applies when no tool override', () {
      const tool = McpToolDescriptor(
        name: 'biz.write',
        sideEffect: McpToolSideEffect.write,
        suggestedPolicy: McpToolPolicyLevel.confirmOnce,
      );
      final level = resolver.resolve(
        server: server.copyWith(
          defaultToolPolicy: McpToolPolicyLevel.autoAllow,
        ),
        tool: tool,
      );
      expect(level, McpToolPolicyLevel.autoAllow);
    });

    test('tool override still wins over server default', () {
      const tool = McpToolDescriptor(
        name: 'biz.write',
        sideEffect: McpToolSideEffect.write,
      );
      final level = resolver.resolve(
        server: server.copyWith(
          defaultToolPolicy: McpToolPolicyLevel.autoAllow,
          toolPolicyOverrides: {
            'biz.write': McpToolPolicyLevel.deny,
          },
        ),
        tool: tool,
      );
      expect(level, McpToolPolicyLevel.deny);
    });

    test('confirmOnce + session grant → effective autoAllow', () {
      const tool = McpToolDescriptor(
        name: 'biz.write',
        sideEffect: McpToolSideEffect.write,
        suggestedPolicy: McpToolPolicyLevel.confirmOnce,
      );
      final grants = McpSessionToolGrants()..grant(server.id, tool.name);
      expect(
        resolver.resolveEffective(
          server: server,
          tool: tool,
          sessionGrants: grants,
        ),
        McpToolPolicyLevel.autoAllow,
      );
    });
  });

  group('McpServerConfig / enums', () {
    test('round-trip meta json without secret plaintext', () {
      const original = McpServerConfig(
        id: 'mcp_a',
        displayName: 'A',
        baseUrl: 'https://mcp.local/sse',
        authKind: McpAuthKind.bearer,
        authSecretRef: 'core.mcp.secret.mcp_a',
        defaultToolPolicy: McpToolPolicyLevel.confirmOnce,
        toolPolicyOverrides: {
          't1': McpToolPolicyLevel.confirmAlways,
        },
        toolsCache: [
          McpToolDescriptor(
            name: 't1',
            title: '查询',
            sideEffect: McpToolSideEffect.read,
          ),
        ],
      );
      final meta = original.toJsonMeta();
      expect(meta.containsKey('apiKey'), isFalse);
      expect(meta['authSecretRef'], 'core.mcp.secret.mcp_a');
      expect(meta['defaultToolPolicy'], 'confirm_once');
      final restored = McpServerConfig.fromJson(meta);
      expect(restored.id, original.id);
      expect(restored.authKind, McpAuthKind.bearer);
      expect(restored.defaultToolPolicy, McpToolPolicyLevel.confirmOnce);
      expect(restored.toolPolicyOverrides['t1'], McpToolPolicyLevel.confirmAlways);
      expect(restored.toolsCache.single.name, 't1');
    });

    test('policy wire names align with DESIGN', () {
      expect(McpToolPolicyLevel.confirmAlways.wire, 'confirm_always');
      expect(McpToolPolicyLevel.tryParse('auto_allow'), McpToolPolicyLevel.autoAllow);
    });
  });

  group('McpAuthProvider', () {
    test('NoneMcpAuth returns empty headers', () async {
      final h = await const NoneMcpAuth().headers();
      expect(h, isEmpty);
    });

    test('BearerMcpAuth from SecretStore', () async {
      final store = MemorySecretStore({'ref1': 'tok-abc'});
      final auth = BearerMcpAuth(secretStore: store, secretRef: 'ref1');
      final h = await auth.headers();
      expect(h['Authorization'], 'Bearer tok-abc');
    });
  });
}
