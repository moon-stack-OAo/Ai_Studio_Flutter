import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseMcpConfigJson', () {
    test('OpenCode mcp local command array', () {
      const raw = '''
{
  "mcp": {
    "dbx": {
      "type": "local",
      "command": ["C:\\\\Tools\\\\node.exe", "C:\\\\mcp\\\\dbx-mcp-server.js"],
      "environment": { "DBX_TOKEN": "secret" }
    }
  }
}
''';
      final r = parseMcpConfigJson(raw);
      expect(r.errors, isEmpty);
      expect(r.entries, hasLength(1));
      final e = r.entries.single;
      expect(e.name, 'dbx');
      expect(e.draft.displayName, 'dbx');
      expect(e.draft.transport, McpTransport.stdio);
      expect(e.draft.command, r'C:\Tools\node.exe');
      expect(e.draft.args, [r'C:\mcp\dbx-mcp-server.js']);
      expect(e.draft.env['DBX_TOKEN'], 'secret');
      expect(e.bearerToken, isNull);
    });

    test('Cursor style command + args', () {
      const raw = '''
{
  "mcpServers": {
    "dbx": {
      "command": "npx",
      "args": ["-y", "@dbx-app/mcp-server"],
      "env": {}
    }
  }
}
''';
      final r = parseMcpConfigJson(raw);
      expect(r.errors, isEmpty);
      expect(r.entries, hasLength(1));
      final d = r.entries.single.draft;
      expect(d.transport, McpTransport.stdio);
      expect(d.command, 'npx');
      expect(d.args, ['-y', '@dbx-app/mcp-server']);
      expect(d.env, isEmpty);
    });

    test('native mcpServers http + bearer header', () {
      const raw = '''
{
  "mcpServers": {
    "biz": {
      "transport": "http",
      "url": "https://mcp.example.com/mcp",
      "headers": {
        "Authorization": "Bearer TOKEN-XYZ"
      }
    }
  }
}
''';
      final r = parseMcpConfigJson(raw);
      expect(r.errors, isEmpty);
      expect(r.entries, hasLength(1));
      final e = r.entries.single;
      expect(e.draft.transport, McpTransport.http);
      expect(e.draft.baseUrl, 'https://mcp.example.com/mcp');
      expect(e.draft.authKind, McpAuthKind.bearer);
      expect(e.bearerToken, 'TOKEN-XYZ');
      expect(e.warnings, isNotEmpty);
    });

    test('allowStdio=false skips stdio', () {
      const raw = '''
{
  "mcpServers": {
    "local": { "command": "node", "args": ["a.js"] },
    "remote": { "url": "https://mcp.example.com/mcp" }
  }
}
''';
      final r = parseMcpConfigJson(raw, allowStdio: false);
      expect(r.errors, isEmpty);
      expect(r.entries, hasLength(1));
      expect(r.entries.single.name, 'remote');
      expect(r.skipped, hasLength(1));
      expect(r.skipped.single, contains('local'));
      expect(r.skipped.single, contains('仅桌面'));
    });

    test('illegal JSON', () {
      final r = parseMcpConfigJson('{ not json');
      expect(r.entries, isEmpty);
      expect(r.errors, isNotEmpty);
      expect(r.errors.first, contains('JSON'));
    });

    test('empty object without servers map', () {
      final r = parseMcpConfigJson('{}');
      expect(r.entries, isEmpty);
      expect(r.errors, isNotEmpty);
      expect(r.errors.first, contains('mcp'));
    });

    test('stdio missing command skipped; http missing url skipped', () {
      const raw = '''
{
  "mcpServers": {
    "a": { "transport": "stdio" },
    "b": { "transport": "http" },
    "c": { "transport": "stdio", "command": "node", "args": ["x.js"] }
  }
}
''';
      final r = parseMcpConfigJson(raw);
      expect(r.entries, hasLength(1));
      expect(r.entries.single.name, 'c');
      expect(r.skipped, hasLength(2));
    });

    test('OpenCode type remote + url', () {
      const raw = '''
{
  "mcp": {
    "svc": {
      "type": "remote",
      "url": "https://svc.example/mcp"
    }
  }
}
''';
      final r = parseMcpConfigJson(raw);
      expect(r.entries.single.draft.transport, McpTransport.http);
      expect(r.entries.single.draft.baseUrl, 'https://svc.example/mcp');
    });

    test('VS Code servers key', () {
      const raw = '''
{
  "servers": {
    "s1": { "command": "uvx", "args": ["demo"] }
  }
}
''';
      final r = parseMcpConfigJson(raw);
      expect(r.entries, hasLength(1));
      expect(r.entries.single.draft.command, 'uvx');
    });

    test('uniqueMcpImportDisplayName suffixes', () {
      expect(uniqueMcpImportDisplayName('dbx', []), 'dbx');
      expect(uniqueMcpImportDisplayName('dbx', ['dbx']), 'dbx (2)');
      expect(
        uniqueMcpImportDisplayName('dbx', ['dbx', 'dbx (2)']),
        'dbx (3)',
      );
    });
  });
}
