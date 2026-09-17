import 'dart:convert';

import 'mcp_models.dart';

/// 将 MCP tools 缓存转为 OpenAI 兼容 `tools[]`（function calling）。
///
/// [inputSchemaSummary] 若为合法 JSON Schema 对象则原样放入 `parameters`；
/// 否则使用空 object schema（`additionalProperties: true`）。
List<Map<String, dynamic>> mcpToolsToOpenAiTools(
  Iterable<McpToolDescriptor> tools,
) {
  final out = <Map<String, dynamic>>[];
  final seen = <String>{};
  for (final t in tools) {
    final name = t.name.trim();
    if (name.isEmpty || !seen.add(name)) continue;
    final desc = (t.description ?? t.title ?? '').trim();
    out.add({
      'type': 'function',
      'function': {
        'name': name,
        if (desc.isNotEmpty) 'description': desc,
        'parameters': _parametersFromSummary(t.inputSchemaSummary),
      },
    });
  }
  return out;
}

Map<String, dynamic> _parametersFromSummary(String? summary) {
  final raw = summary?.trim() ?? '';
  if (raw.startsWith('{')) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
  }
  return const {
    'type': 'object',
    'additionalProperties': true,
  };
}

/// 在已启用 Server 中按 tool 名解析归属（同名取首个）。
McpServerConfig? resolveServerForTool(
  Iterable<McpServerConfig> enabledServers,
  String toolName,
) {
  final name = toolName.trim();
  if (name.isEmpty) return null;
  for (final s in enabledServers) {
    for (final t in s.toolsCache) {
      if (t.name == name) return s;
    }
  }
  return null;
}

/// 在 Server 缓存中查找 tool 描述；找不到则合成 unknown 占位。
McpToolDescriptor resolveToolDescriptor(
  McpServerConfig server,
  String toolName,
) {
  final name = toolName.trim();
  for (final t in server.toolsCache) {
    if (t.name == name) return t;
  }
  return McpToolDescriptor(
    name: name.isEmpty ? 'unknown' : name,
    sideEffect: McpToolSideEffect.unknown,
  );
}
