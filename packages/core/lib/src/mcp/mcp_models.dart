/// 业务 MCP 模型与枚举（DESIGN.md §5.11 · P6）。
///
/// 聊天主路径 tool 消息见 `chat_models.dart`（P6-1）；本文件含轨迹/策略类型。
/// HTTP Streamable JSON-RPC Client 与 Facade 编排见 P6-2（已落地子集）。
library;

/// MCP 传输方式（DESIGN §5.11.5 · P6-S）。
///
/// [http] 双端；[stdio] 仅桌面（经 [ProcessHost]）。
enum McpTransport {
  http,
  stdio;

  String get wire => name;

  static McpTransport? tryParse(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'http':
      case 'sse':
      case 'http+sse':
        return McpTransport.http;
      case 'stdio':
      case 'local':
        return McpTransport.stdio;
      default:
        return null;
    }
  }
}

/// MCP 鉴权种类（首期实现 [none] / [bearer]；[oauth] 仅预留）。
enum McpAuthKind {
  none,
  bearer,
  oauth;

  String get wire => name;

  static McpAuthKind? tryParse(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'none':
        return McpAuthKind.none;
      case 'bearer':
        return McpAuthKind.bearer;
      case 'oauth':
        return McpAuthKind.oauth;
      default:
        return null;
    }
  }
}

/// Tool 副作用提示（缺省按 write 对待）。
enum McpToolSideEffect {
  read,
  write,
  unknown;

  String get wire => name;

  static McpToolSideEffect tryParse(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'read':
        return McpToolSideEffect.read;
      case 'write':
        return McpToolSideEffect.write;
      default:
        return McpToolSideEffect.unknown;
    }
  }
}

/// 分级授权级别（DESIGN §5.11.4）。
enum McpToolPolicyLevel {
  deny,
  confirmAlways,
  confirmOnce,
  autoAllow;

  /// 与 SET-MCP-POLICY / 规格文案对齐的 wire 名。
  String get wire => switch (this) {
        McpToolPolicyLevel.deny => 'deny',
        McpToolPolicyLevel.confirmAlways => 'confirm_always',
        McpToolPolicyLevel.confirmOnce => 'confirm_once',
        McpToolPolicyLevel.autoAllow => 'auto_allow',
      };

  static McpToolPolicyLevel? tryParse(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'deny':
        return McpToolPolicyLevel.deny;
      case 'confirm_always':
      case 'confirmalways':
        return McpToolPolicyLevel.confirmAlways;
      case 'confirm_once':
      case 'confirmonce':
        return McpToolPolicyLevel.confirmOnce;
      case 'auto_allow':
      case 'autoallow':
        return McpToolPolicyLevel.autoAllow;
      default:
        return null;
    }
  }
}

/// 单次 tool 调用在聊天轨迹中的状态（CHAT-TOOL-CALL）。
enum McpToolCallStatus {
  /// 排队等待策略/授权。
  queued,

  /// 等待用户授权确认。
  pendingAuth,

  /// 正在执行 `tools/call`。
  running,

  /// 成功。
  success,

  /// 执行失败（含超时）。
  failed,

  /// 策略拒绝或用户拒绝。
  rejected,

  /// 用户停止 / 取消。
  cancelled;

  String get wire => switch (this) {
        McpToolCallStatus.queued => 'queued',
        McpToolCallStatus.pendingAuth => 'pending_auth',
        McpToolCallStatus.running => 'running',
        McpToolCallStatus.success => 'success',
        McpToolCallStatus.failed => 'failed',
        McpToolCallStatus.rejected => 'rejected',
        McpToolCallStatus.cancelled => 'cancelled',
      };

  static McpToolCallStatus? tryParse(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'queued':
        return McpToolCallStatus.queued;
      case 'pending_auth':
      case 'pendingauth':
        return McpToolCallStatus.pendingAuth;
      case 'running':
        return McpToolCallStatus.running;
      case 'success':
        return McpToolCallStatus.success;
      case 'failed':
        return McpToolCallStatus.failed;
      case 'rejected':
        return McpToolCallStatus.rejected;
      case 'cancelled':
      case 'canceled':
        return McpToolCallStatus.cancelled;
      default:
        return null;
    }
  }
}

/// Server 连通性探测结果摘要。
enum McpProbeStatus {
  unknown,
  probing,
  ready,
  error;

  String get wire => name;

  static McpProbeStatus tryParse(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'probing':
        return McpProbeStatus.probing;
      case 'ready':
        return McpProbeStatus.ready;
      case 'error':
        return McpProbeStatus.error;
      default:
        return McpProbeStatus.unknown;
    }
  }
}

/// MCP Server 配置（逻辑字段对齐 §5.11.5；密钥仅存 [authSecretRef]）。
class McpServerConfig {
  const McpServerConfig({
    required this.id,
    required this.displayName,
    this.transport = McpTransport.http,
    this.baseUrl = '',
    this.command,
    this.args = const [],
    this.env = const {},
    this.cwd,
    this.enabled = true,
    this.authKind = McpAuthKind.none,
    this.authSecretRef,
    this.defaultToolPolicy,
    this.toolPolicyOverrides = const {},
    this.toolsCache = const [],
    this.lastProbeAtMs,
    this.lastError,
    this.probeStatus = McpProbeStatus.unknown,
    this.callTimeoutSeconds,
  });

  final String id;
  final String displayName;

  /// 传输：默认 [McpTransport.http]；[McpTransport.stdio] 仅桌面。
  final McpTransport transport;

  /// HTTP/SSE 入口；[transport] 为 stdio 时忽略。
  final String baseUrl;

  /// stdio 可执行文件路径或命令名（如 `node`）。
  final String? command;

  /// stdio 参数列表。
  final List<String> args;

  /// stdio 额外环境变量。
  ///
  /// prefs [toJsonMeta] 可原样持久化非空 env；**备份默认**经 [toJsonForBackup]
  /// 在 `includeSecrets: false` 时清空（含密钥的值勿依赖默认备份）。
  final Map<String, String> env;

  /// stdio 工作目录（可选）。
  final String? cwd;

  final bool enabled;
  final McpAuthKind authKind;

  /// 指向 [SecretStore] 的引用键；禁止把 token 写入会话 JSON。
  final String? authSecretRef;

  /// 本 Server 默认授权（无单 tool 覆盖时生效；空=按副作用/元数据）。
  final McpToolPolicyLevel? defaultToolPolicy;

  /// `toolName → 级别` 用户覆盖（SET-MCP-POLICY）。
  final Map<String, McpToolPolicyLevel> toolPolicyOverrides;

  /// 最近一次 `tools/list` 缓存。
  final List<McpToolDescriptor> toolsCache;

  final int? lastProbeAtMs;
  final String? lastError;
  final McpProbeStatus probeStatus;

  /// 单次 `tools/call` 超时秒数；空则用编排默认（建议 30s）。
  final int? callTimeoutSeconds;

  bool get hasBaseUrl => baseUrl.trim().isNotEmpty;

  bool get hasCommand => command?.trim().isNotEmpty == true;

  /// 是否可向模型暴露 tools。
  ///
  /// - http：启用且有 baseUrl
  /// - stdio：启用且有 command
  bool get canExposeTools {
    if (!enabled) return false;
    return switch (transport) {
      McpTransport.http => hasBaseUrl,
      McpTransport.stdio => hasCommand,
    };
  }

  McpServerConfig copyWith({
    String? id,
    String? displayName,
    McpTransport? transport,
    String? baseUrl,
    String? command,
    bool clearCommand = false,
    List<String>? args,
    Map<String, String>? env,
    String? cwd,
    bool clearCwd = false,
    bool? enabled,
    McpAuthKind? authKind,
    String? authSecretRef,
    bool clearAuthSecretRef = false,
    McpToolPolicyLevel? defaultToolPolicy,
    bool clearDefaultToolPolicy = false,
    Map<String, McpToolPolicyLevel>? toolPolicyOverrides,
    List<McpToolDescriptor>? toolsCache,
    int? lastProbeAtMs,
    bool clearLastProbeAtMs = false,
    String? lastError,
    bool clearLastError = false,
    McpProbeStatus? probeStatus,
    int? callTimeoutSeconds,
    bool clearCallTimeoutSeconds = false,
  }) {
    return McpServerConfig(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      transport: transport ?? this.transport,
      baseUrl: baseUrl ?? this.baseUrl,
      command: clearCommand ? null : (command ?? this.command),
      args: args ?? this.args,
      env: env ?? this.env,
      cwd: clearCwd ? null : (cwd ?? this.cwd),
      enabled: enabled ?? this.enabled,
      authKind: authKind ?? this.authKind,
      authSecretRef: clearAuthSecretRef
          ? null
          : (authSecretRef ?? this.authSecretRef),
      defaultToolPolicy: clearDefaultToolPolicy
          ? null
          : (defaultToolPolicy ?? this.defaultToolPolicy),
      toolPolicyOverrides: toolPolicyOverrides ?? this.toolPolicyOverrides,
      toolsCache: toolsCache ?? this.toolsCache,
      lastProbeAtMs: clearLastProbeAtMs
          ? null
          : (lastProbeAtMs ?? this.lastProbeAtMs),
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      probeStatus: probeStatus ?? this.probeStatus,
      callTimeoutSeconds: clearCallTimeoutSeconds
          ? null
          : (callTimeoutSeconds ?? this.callTimeoutSeconds),
    );
  }

  /// 元数据 JSON（不含 Bearer 明文；prefs 用）。
  ///
  /// stdio `env` 非空时写入（本机 prefs）；备份请用 [toJsonForBackup]。
  Map<String, dynamic> toJsonMeta() => {
        'id': id,
        'displayName': displayName,
        'transport': transport.wire,
        'baseUrl': baseUrl,
        if (command != null && command!.trim().isNotEmpty) 'command': command,
        if (args.isNotEmpty) 'args': args,
        if (env.isNotEmpty) 'env': env,
        if (cwd != null && cwd!.trim().isNotEmpty) 'cwd': cwd,
        'enabled': enabled,
        'authKind': authKind.wire,
        if (authSecretRef != null && authSecretRef!.isNotEmpty)
          'authSecretRef': authSecretRef,
        if (defaultToolPolicy != null)
          'defaultToolPolicy': defaultToolPolicy!.wire,
        if (toolPolicyOverrides.isNotEmpty)
          'toolPolicyOverrides': {
            for (final e in toolPolicyOverrides.entries) e.key: e.value.wire,
          },
        if (toolsCache.isNotEmpty)
          'toolsCache': toolsCache.map((t) => t.toJson()).toList(),
        if (lastProbeAtMs != null) 'lastProbeAtMs': lastProbeAtMs,
        if (lastError != null) 'lastError': lastError,
        'probeStatus': probeStatus.wire,
        if (callTimeoutSeconds != null)
          'callTimeoutSeconds': callTimeoutSeconds,
      };

  /// 备份导出用：剥离本机 [authSecretRef]；含密钥时写入 [authToken] 明文。
  ///
  /// [includeSecrets] 为 false 时清空 stdio [env]（默认备份 omit 密钥）。
  Map<String, dynamic> toJsonForBackup({
    String? authToken,
    bool includeSecrets = false,
  }) {
    final map = Map<String, dynamic>.from(toJsonMeta())..remove('authSecretRef');
    if (!includeSecrets) {
      map.remove('env');
    }
    final token = authToken?.trim() ?? '';
    if (token.isNotEmpty) {
      map['authToken'] = token;
    }
    return map;
  }

  factory McpServerConfig.fromJson(Map<String, dynamic> json) {
    final overrides = <String, McpToolPolicyLevel>{};
    final rawOverrides = json['toolPolicyOverrides'];
    if (rawOverrides is Map) {
      for (final e in rawOverrides.entries) {
        final level = McpToolPolicyLevel.tryParse(e.value?.toString());
        final name = e.key.toString().trim();
        if (name.isEmpty || level == null) continue;
        overrides[name] = level;
      }
    }
    final tools = <McpToolDescriptor>[];
    final rawTools = json['toolsCache'];
    if (rawTools is List) {
      for (final e in rawTools) {
        if (e is Map) {
          tools.add(McpToolDescriptor.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    final secretRef = json['authSecretRef']?.toString();
    final args = <String>[];
    final rawArgs = json['args'];
    if (rawArgs is List) {
      for (final e in rawArgs) {
        if (e == null) continue;
        args.add(e.toString());
      }
    }
    final env = <String, String>{};
    final rawEnv = json['env'];
    if (rawEnv is Map) {
      for (final e in rawEnv.entries) {
        final k = e.key.toString();
        if (k.isEmpty) continue;
        env[k] = e.value?.toString() ?? '';
      }
    }
    final commandRaw = json['command']?.toString();
    final cwdRaw = json['cwd']?.toString();
    return McpServerConfig(
      id: json['id']?.toString().trim().isNotEmpty == true
          ? json['id'].toString().trim()
          : 'mcp_unknown',
      displayName: json['displayName']?.toString().trim().isNotEmpty == true
          ? json['displayName'].toString().trim()
          : '未命名 MCP',
      transport: McpTransport.tryParse(json['transport']?.toString()) ??
          McpTransport.http,
      baseUrl: json['baseUrl']?.toString().trim() ?? '',
      command: (commandRaw == null || commandRaw.trim().isEmpty)
          ? null
          : commandRaw.trim(),
      args: args,
      env: env,
      cwd: (cwdRaw == null || cwdRaw.trim().isEmpty) ? null : cwdRaw.trim(),
      enabled: json['enabled'] != false,
      authKind: McpAuthKind.tryParse(json['authKind']?.toString()) ??
          McpAuthKind.none,
      authSecretRef:
          (secretRef == null || secretRef.isEmpty) ? null : secretRef,
      defaultToolPolicy:
          McpToolPolicyLevel.tryParse(json['defaultToolPolicy']?.toString()),
      toolPolicyOverrides: overrides,
      toolsCache: tools,
      lastProbeAtMs: (json['lastProbeAtMs'] as num?)?.toInt(),
      lastError: json['lastError']?.toString(),
      probeStatus: McpProbeStatus.tryParse(json['probeStatus']?.toString()),
      callTimeoutSeconds: (json['callTimeoutSeconds'] as num?)?.toInt(),
    );
  }

  @override
  String toString() =>
      'McpServerConfig(id: $id, displayName: $displayName, '
      'transport: ${transport.wire}, baseUrl: $baseUrl, '
      'command: $command, enabled: $enabled, authKind: ${authKind.wire})';
}

/// `tools/list` 单项描述（缓存用）。
class McpToolDescriptor {
  const McpToolDescriptor({
    required this.name,
    this.title,
    this.description,
    this.sideEffect = McpToolSideEffect.unknown,
    this.inputSchemaSummary,
    this.suggestedPolicy,
  });

  final String name;
  final String? title;
  final String? description;
  final McpToolSideEffect sideEffect;

  /// 输入 schema 摘要（非完整 JSON Schema；供 UI / 授权卡）。
  final String? inputSchemaSummary;

  /// Server/tool 元数据建议的策略级别（可被用户覆盖）。
  final McpToolPolicyLevel? suggestedPolicy;

  String get displayTitle {
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    return name;
  }

  McpToolDescriptor copyWith({
    String? name,
    String? title,
    bool clearTitle = false,
    String? description,
    bool clearDescription = false,
    McpToolSideEffect? sideEffect,
    String? inputSchemaSummary,
    bool clearInputSchemaSummary = false,
    McpToolPolicyLevel? suggestedPolicy,
    bool clearSuggestedPolicy = false,
  }) {
    return McpToolDescriptor(
      name: name ?? this.name,
      title: clearTitle ? null : (title ?? this.title),
      description:
          clearDescription ? null : (description ?? this.description),
      sideEffect: sideEffect ?? this.sideEffect,
      inputSchemaSummary: clearInputSchemaSummary
          ? null
          : (inputSchemaSummary ?? this.inputSchemaSummary),
      suggestedPolicy: clearSuggestedPolicy
          ? null
          : (suggestedPolicy ?? this.suggestedPolicy),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (title != null && title!.isNotEmpty) 'title': title,
        if (description != null && description!.isNotEmpty)
          'description': description,
        'sideEffect': sideEffect.wire,
        if (inputSchemaSummary != null && inputSchemaSummary!.isNotEmpty)
          'inputSchemaSummary': inputSchemaSummary,
        if (suggestedPolicy != null) 'suggestedPolicy': suggestedPolicy!.wire,
      };

  factory McpToolDescriptor.fromJson(Map<String, dynamic> json) {
    return McpToolDescriptor(
      name: json['name']?.toString().trim() ?? '',
      title: json['title']?.toString(),
      description: json['description']?.toString(),
      sideEffect: McpToolSideEffect.tryParse(json['sideEffect']?.toString()),
      inputSchemaSummary: json['inputSchemaSummary']?.toString(),
      suggestedPolicy:
          McpToolPolicyLevel.tryParse(json['suggestedPolicy']?.toString()),
    );
  }
}

/// 模型发起的单次 tool 调用请求（编排输入）。
class McpToolCallRequest {
  const McpToolCallRequest({
    required this.toolCallId,
    required this.serverId,
    required this.toolName,
    this.argumentsJson = '{}',
    this.argumentsSummary,
  });

  /// 与 OpenAI `tool_call_id` 对齐。
  final String toolCallId;
  final String serverId;
  final String toolName;

  /// 原始参数 JSON 字符串（日志/UI 须脱敏截断）。
  final String argumentsJson;

  /// 已截断/脱敏的参数摘要（授权卡用）。
  final String? argumentsSummary;
}

/// `tools/call` 结果（回灌模型用）。
class McpToolCallResult {
  const McpToolCallResult({
    required this.toolCallId,
    required this.status,
    this.content = '',
    this.isError = false,
    this.errorMessage,
    this.latencyMs,
  });

  final String toolCallId;
  final McpToolCallStatus status;

  /// 回灌给模型的文本内容（成功或拒绝说明）。
  final String content;
  final bool isError;
  final String? errorMessage;
  final int? latencyMs;

  bool get isSuccess => status == McpToolCallStatus.success && !isError;
}

/// 聊天侧工具轨迹轻量类型（CHAT-TOOL-CALL UI / 编排）。
///
/// 协议层 OpenAI `tool_calls` 见 [ChatToolCall]；本类型承载授权与执行状态摘要。
class ChatToolCallTrace {
  const ChatToolCallTrace({
    required this.toolCallId,
    required this.serverId,
    required this.serverDisplayName,
    required this.toolName,
    this.toolTitle,
    this.sideEffect = McpToolSideEffect.unknown,
    this.status = McpToolCallStatus.queued,
    this.argumentsSummary,
    this.resultSummary,
    this.errorMessage,
  });

  final String toolCallId;
  final String serverId;
  final String serverDisplayName;
  final String toolName;
  final String? toolTitle;
  final McpToolSideEffect sideEffect;
  final McpToolCallStatus status;
  final String? argumentsSummary;
  final String? resultSummary;
  final String? errorMessage;

  ChatToolCallTrace copyWith({
    McpToolCallStatus? status,
    String? argumentsSummary,
    String? resultSummary,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return ChatToolCallTrace(
      toolCallId: toolCallId,
      serverId: serverId,
      serverDisplayName: serverDisplayName,
      toolName: toolName,
      toolTitle: toolTitle,
      sideEffect: sideEffect,
      status: status ?? this.status,
      argumentsSummary: argumentsSummary ?? this.argumentsSummary,
      resultSummary: resultSummary ?? this.resultSummary,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }

  Map<String, dynamic> toJson() => {
        'toolCallId': toolCallId,
        'serverId': serverId,
        'serverDisplayName': serverDisplayName,
        'toolName': toolName,
        if (toolTitle != null) 'toolTitle': toolTitle,
        'sideEffect': sideEffect.wire,
        'status': status.wire,
        if (argumentsSummary != null) 'argumentsSummary': argumentsSummary,
        if (resultSummary != null) 'resultSummary': resultSummary,
        if (errorMessage != null) 'errorMessage': errorMessage,
      };

  factory ChatToolCallTrace.fromJson(Map<String, dynamic> json) {
    return ChatToolCallTrace(
      toolCallId: json['toolCallId']?.toString() ?? '',
      serverId: json['serverId']?.toString() ?? '',
      serverDisplayName: json['serverDisplayName']?.toString() ?? '',
      toolName: json['toolName']?.toString() ?? '',
      toolTitle: json['toolTitle']?.toString(),
      sideEffect: McpToolSideEffect.tryParse(json['sideEffect']?.toString()),
      status: McpToolCallStatus.tryParse(json['status']?.toString()) ??
          McpToolCallStatus.queued,
      argumentsSummary: json['argumentsSummary']?.toString(),
      resultSummary: json['resultSummary']?.toString(),
      errorMessage: json['errorMessage']?.toString(),
    );
  }
}

/// 默认单次用户发送触发的 tool 循环硬上限（§5.11.3）。
const int kDefaultMcpMaxToolRounds = 8;

/// 默认单次 `tools/call` 超时。
const Duration kDefaultMcpCallTimeout = Duration(seconds: 30);
