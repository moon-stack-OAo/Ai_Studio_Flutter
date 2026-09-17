/// 标准 MCP 配置 JSON 导入解析（DESIGN.md §5.11.5）。
///
/// ## 本 App 推荐格式（可多 server）
///
/// ```json
/// {
///   "mcpServers": {
///     "dbx": {
///       "transport": "stdio",
///       "command": "C:\\...\\node.exe",
///       "args": ["C:\\...\\dbx-mcp-server.js"],
///       "env": {},
///       "cwd": null
///     },
///     "biz": {
///       "transport": "http",
///       "url": "https://mcp.example.com/mcp",
///       "headers": { "Authorization": "Bearer TOKEN" }
///     }
///   }
/// }
/// ```
///
/// 字段别名：
/// - `url` / `baseUrl` → [McpServerConfig.baseUrl]
/// - `transport`: `http` | `sse` | `stdio` | `local`（`local`→stdio）
/// - 无 transport 但有 `command` → stdio；有 `url`/`baseUrl` → http
///
/// ## 兼容 OpenCode
///
/// 顶层键可为 `mcp` / `mcpServers` / `servers`（VS Code）。
/// - `type: local` → stdio；`command` 为数组时首元=command、其余=args
/// - `environment` 或 `env` → env
/// - remote/http：`type: remote|http|sse` + `url`
///
/// ## 兼容 Cursor
///
/// `mcpServers.<name>.command` / `args` / `env`（无 transport 时按 command 推断 stdio）。
///
/// 解析结果为草稿字段；调用方用 [McpServerRepository.add] 写入（含可选 Bearer）。
library;

import 'dart:convert';

import 'mcp_models.dart';

/// 单条可导入的 Server 草稿。
class McpConfigImportEntry {
  const McpConfigImportEntry({
    required this.name,
    required this.draft,
    this.bearerToken,
    this.warnings = const [],
  });

  /// 配置键名（映射为 displayName 基础名）。
  final String name;

  /// 草稿配置：无稳定 id（占位 `mcp_import_*`）；密钥不在此明文持久化意图。
  final McpServerConfig draft;

  /// 从 `Authorization: Bearer …` 抽出的明文，供 [McpServerRepository.add] /
  /// [McpServerRepository.writeBearerSecret]。
  final String? bearerToken;

  /// 条目级提示（非致命）。
  final List<String> warnings;
}

/// 整包解析结果。
class McpConfigImportResult {
  const McpConfigImportResult({
    this.entries = const [],
    this.errors = const [],
    this.skipped = const [],
  });

  final List<McpConfigImportEntry> entries;
  final List<String> errors;
  final List<String> skipped;

  bool get hasEntries => entries.isNotEmpty;
  bool get hasErrors => errors.isNotEmpty;
}

/// 解析 OpenCode / Cursor / 本 App 风格的 MCP 配置 JSON。
///
/// [allowStdio] 为 false（移动端）时，stdio 项进入 [McpConfigImportResult.skipped]。
McpConfigImportResult parseMcpConfigJson(
  String raw, {
  bool allowStdio = true,
}) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return const McpConfigImportResult(errors: ['配置为空']);
  }

  late final Object? decoded;
  try {
    decoded = jsonDecode(trimmed);
  } on FormatException catch (e) {
    return McpConfigImportResult(
      errors: ['JSON 解析失败：${e.message}'],
    );
  } catch (e) {
    return McpConfigImportResult(errors: ['JSON 解析失败：$e']);
  }

  if (decoded is! Map) {
    return const McpConfigImportResult(errors: ['根节点须为 JSON 对象']);
  }
  final root = Map<String, dynamic>.from(decoded);

  final serversMap = _extractServersMap(root);
  if (serversMap == null) {
    return const McpConfigImportResult(
      errors: [
        '找不到 mcp / mcpServers / servers 对象；'
            '请使用本 App 推荐的 mcpServers，或 OpenCode 的 mcp',
      ],
    );
  }
  if (serversMap.isEmpty) {
    return const McpConfigImportResult(errors: ['Server 列表为空']);
  }

  final entries = <McpConfigImportEntry>[];
  final skipped = <String>[];

  for (final e in serversMap.entries) {
    final key = e.key.toString().trim();
    if (key.isEmpty) {
      skipped.add('(空键名)：跳过');
      continue;
    }
    if (e.value is! Map) {
      skipped.add('$key：配置须为对象');
      continue;
    }
    final body = Map<String, dynamic>.from(e.value as Map);
    final parsed = _parseOneServer(
      name: key,
      body: body,
      allowStdio: allowStdio,
    );
    if (parsed.skipReason != null) {
      skipped.add('$key：${parsed.skipReason}');
      continue;
    }
    entries.add(parsed.entry!);
  }

  return McpConfigImportResult(entries: entries, skipped: skipped);
}

Map<String, dynamic>? _extractServersMap(Map<String, dynamic> root) {
  for (final key in const ['mcpServers', 'mcp', 'servers']) {
    final v = root[key];
    if (v is Map) {
      return Map<String, dynamic>.from(v);
    }
  }
  // 单层：根即 server 名→配置（少见；仅当值全是 Map 且含典型字段时不采用，避免误判）
  return null;
}

class _OneParse {
  const _OneParse.ok(this.entry) : skipReason = null;
  const _OneParse.skip(this.skipReason) : entry = null;

  final McpConfigImportEntry? entry;
  final String? skipReason;
}

_OneParse _parseOneServer({
  required String name,
  required Map<String, dynamic> body,
  required bool allowStdio,
}) {
  final warnings = <String>[];

  final transport = _resolveTransport(body);
  if (transport == null) {
    return const _OneParse.skip('无法判定 transport（需 command 或 url/baseUrl）');
  }

  if (transport == McpTransport.stdio && !allowStdio) {
    return const _OneParse.skip('本地 stdio 仅桌面支持');
  }

  String? command;
  var args = <String>[];
  final env = <String, String>{};
  String? cwd;
  var baseUrl = '';
  String? bearerToken;
  var authKind = McpAuthKind.none;

  if (transport == McpTransport.stdio) {
    final cmdParsed = _parseCommandArgs(body);
    command = cmdParsed.command;
    args = cmdParsed.args;
    if (command == null || command.trim().isEmpty) {
      return const _OneParse.skip('stdio 缺少 command');
    }
    command = command.trim();

    final envRaw = body['env'] ?? body['environment'];
    if (envRaw is Map) {
      for (final ee in envRaw.entries) {
        final k = ee.key.toString();
        if (k.isEmpty) continue;
        env[k] = ee.value?.toString() ?? '';
      }
    }

    final cwdRaw = body['cwd'];
    if (cwdRaw != null && cwdRaw.toString().trim().isNotEmpty) {
      cwd = cwdRaw.toString().trim();
    }
  } else {
    final url = (body['url'] ?? body['baseUrl'])?.toString().trim() ?? '';
    if (url.isEmpty) {
      return const _OneParse.skip('HTTP 缺少 url / baseUrl');
    }
    baseUrl = url;

    final headers = body['headers'];
    if (headers is Map) {
      bearerToken = _extractBearer(headers);
      if (bearerToken != null && bearerToken.isNotEmpty) {
        authKind = McpAuthKind.bearer;
      }
    }
  }

  final safeName = _safeIdFragment(name);
  final draft = McpServerConfig(
    id: 'mcp_import_$safeName',
    displayName: name,
    transport: transport,
    baseUrl: baseUrl,
    command: command,
    args: args,
    env: env,
    cwd: cwd,
    enabled: body['enabled'] != false,
    authKind: authKind,
  );

  if (transport == McpTransport.stdio && env.isNotEmpty) {
    warnings.add('含 ${env.length} 项环境变量（可能含密钥，请确认来源）');
  }
  if (bearerToken != null && bearerToken.isNotEmpty) {
    warnings.add('已识别 Bearer Token（将写入本机凭据库，不显示明文）');
  }

  return _OneParse.ok(
    McpConfigImportEntry(
      name: name,
      draft: draft,
      bearerToken: bearerToken,
      warnings: warnings,
    ),
  );
}

McpTransport? _resolveTransport(Map<String, dynamic> body) {
  final explicit = McpTransport.tryParse(
    body['transport']?.toString() ?? body['type']?.toString(),
  );
  if (explicit != null) return explicit;

  final typeRaw = (body['type'] ?? '').toString().trim().toLowerCase();
  if (typeRaw == 'remote') return McpTransport.http;

  final hasCommand = body.containsKey('command') && body['command'] != null;
  final hasUrl = ((body['url'] ?? body['baseUrl'])?.toString().trim() ?? '')
      .isNotEmpty;
  if (hasCommand) return McpTransport.stdio;
  if (hasUrl) return McpTransport.http;
  return null;
}

({String? command, List<String> args}) _parseCommandArgs(
  Map<String, dynamic> body,
) {
  final raw = body['command'];
  if (raw is List) {
    final parts = <String>[];
    for (final e in raw) {
      if (e == null) continue;
      final s = e.toString();
      if (s.isNotEmpty) parts.add(s);
    }
    if (parts.isEmpty) return (command: null, args: const []);
    final rest = body['args'];
    final extra = <String>[];
    if (rest is List) {
      for (final e in rest) {
        if (e == null) continue;
        extra.add(e.toString());
      }
    }
    return (
      command: parts.first,
      args: [...parts.skip(1), ...extra],
    );
  }

  final cmd = raw?.toString().trim();
  final args = <String>[];
  final rawArgs = body['args'];
  if (rawArgs is List) {
    for (final e in rawArgs) {
      if (e == null) continue;
      args.add(e.toString());
    }
  } else if (rawArgs is String && rawArgs.trim().isNotEmpty) {
    args.add(rawArgs.trim());
  }
  return (
    command: (cmd == null || cmd.isEmpty) ? null : cmd,
    args: args,
  );
}

String? _extractBearer(Map headers) {
  String? auth;
  for (final e in headers.entries) {
    final k = e.key.toString().toLowerCase();
    if (k == 'authorization') {
      auth = e.value?.toString();
      break;
    }
  }
  if (auth == null) return null;
  final t = auth.trim();
  final lower = t.toLowerCase();
  if (lower.startsWith('bearer ')) {
    final token = t.substring(7).trim();
    return token.isEmpty ? null : token;
  }
  return null;
}

String _safeIdFragment(String name) {
  final buf = StringBuffer();
  for (final r in name.runes) {
    final c = String.fromCharCode(r);
    if (RegExp(r'[a-zA-Z0-9_-]').hasMatch(c)) {
      buf.write(c);
    } else {
      buf.write('_');
    }
  }
  final s = buf.toString().replaceAll(RegExp(r'_+'), '_');
  final t = s.replaceAll(RegExp(r'^_|_$'), '');
  return t.isEmpty ? 'server' : (t.length > 48 ? t.substring(0, 48) : t);
}

/// 为导入生成不与已有 [existingNames] 冲突的显示名（同名则后缀 ` (2)`…）。
String uniqueMcpImportDisplayName(
  String baseName,
  Iterable<String> existingNames,
) {
  final base = baseName.trim().isEmpty ? '未命名 MCP' : baseName.trim();
  final taken = existingNames.map((e) => e.trim()).toSet();
  if (!taken.contains(base)) return base;
  for (var i = 2; i < 1000; i++) {
    final candidate = '$base ($i)';
    if (!taken.contains(candidate)) return candidate;
  }
  return '$base (${DateTime.now().millisecondsSinceEpoch})';
}
