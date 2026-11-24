import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../provider/secret_store.dart';
import '../util/id.dart';
import 'mcp_models.dart';

/// MCP Server 列表持久化快照（元数据；密钥仅存 ref）。
class McpServerStoreSnapshot {
  const McpServerStoreSnapshot({required this.servers});

  final List<McpServerConfig> servers;
}

/// 存储抽象（对齐 [ProviderStorage] 风格）。
abstract class McpServerStorage {
  Future<McpServerStoreSnapshot> load();

  Future<void> save(McpServerStoreSnapshot snapshot);
}

/// 内存存储（测试默认）。
class MemoryMcpServerStorage implements McpServerStorage {
  MemoryMcpServerStorage([List<McpServerConfig>? initial])
    : _servers = List<McpServerConfig>.from(initial ?? const []);

  List<McpServerConfig> _servers;

  @override
  Future<McpServerStoreSnapshot> load() async =>
      McpServerStoreSnapshot(servers: List.unmodifiable(_servers));

  @override
  Future<void> save(McpServerStoreSnapshot snapshot) async {
    _servers = List<McpServerConfig>.from(snapshot.servers);
  }
}

/// 生产元数据存储：`shared_preferences` → `core.mcp_servers.v1`（**不含** token）。
///
/// Bearer 明文由 [McpServerRepository] 经 [SecretStore] 按 `authSecretRef` 读写，
/// 对齐 [SecureProviderStorage] 的「prefs 元数据 + SecretStore 密钥」模式。
class PrefsMcpServerStorage implements McpServerStorage {
  PrefsMcpServerStorage({SharedPreferences? prefs, SecretStore? secretStore})
    : _prefsOverride = prefs,
      _secrets = GuardedSecretStore(secretStore ?? FlutterSecureSecretStore());

  static const prefsKey = 'core.mcp_servers.v1';

  final SharedPreferences? _prefsOverride;
  final SecretStore _secrets;
  SharedPreferences? _prefs;
  bool _saving = false;
  bool get hasPendingWrites => _saving || (_secrets as GuardedSecretStore).isPending;

  Future<SharedPreferences> _ensurePrefs() async {
    return _prefs ??= _prefsOverride ?? await SharedPreferences.getInstance();
  }

  @override
  Future<McpServerStoreSnapshot> load() async {
    if (hasPendingWrites) throw StateError('安全存储仍在处理中');
    final prefs = await _ensurePrefs();
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) {
      return const McpServerStoreSnapshot(servers: []);
    }
    final Map decoded;
    try {
      final value = jsonDecode(raw);
      if (value is! Map) return const McpServerStoreSnapshot(servers: []);
      decoded = value;
    } on FormatException {
      return const McpServerStoreSnapshot(servers: []);
    }
    final items = <McpServerConfig>[];
    var migrated = false;
    final listRaw = decoded['servers'];
    if (listRaw is List) {
      for (final entry in listRaw) {
        if (entry is! Map) continue;
        var server = McpServerConfig.fromJson(Map<String, dynamic>.from(entry));
        if (entry.containsKey('env')) {
          // 旧明文仅在安全写入并回读成功后从 prefs 移除。
          if (server.env.isNotEmpty) await _writeEnvironment(server);
          migrated = true;
        } else if (entry['envSecretRef'] ==
            mcpEnvironmentSecretKey(server.id)) {
          final value = await _secrets.read(mcpEnvironmentSecretKey(server.id));
          if (value != null) {
            final env = Map<String, String>.from(jsonDecode(value) as Map);
            server = server.copyWith(env: env);
          }
        }
        if (server.transport == McpTransport.stdio && !server.isStdioApproved) {
          server = server.copyWith(enabled: false, clearStdioApproval: true);
        }
        items.add(server);
      }
    }
    final snapshot = McpServerStoreSnapshot(servers: items);
    if (migrated) await save(snapshot);
    return snapshot;
  }

  Future<void> _writeEnvironment(McpServerConfig server) async {
    final key = mcpEnvironmentSecretKey(server.id);
    final value = jsonEncode(server.env);
    await _secrets.write(key, value);
    if (await _secrets.read(key) != value) {
      throw StateError('MCP 环境变量安全存储回读失败');
    }
  }

  @override
  Future<void> save(McpServerStoreSnapshot snapshot) async {
    if (hasPendingWrites) throw StateError('安全存储仍在处理中');
    _saving = true;
    try {
    final prefs = await _ensurePrefs();
    final previous = prefs.getString(prefsKey);
    final oldEnvironmentIds = <String>{};
    if (previous != null) {
      final decoded = jsonDecode(previous);
      if (decoded is Map && decoded['servers'] is List) {
        for (final entry in decoded['servers'] as List) {
          if (entry is Map && entry['envSecretRef'] != null) {
            oldEnvironmentIds.add(entry['id'].toString());
          }
        }
      }
    }
    final environmentIds = <String>{};
    for (final server in snapshot.servers) {
      if (server.env.isNotEmpty) {
        await _writeEnvironment(server);
        environmentIds.add(server.id);
      }
    }
    final payload = {
      'servers': [for (final s in snapshot.servers) s.toJsonMeta()],
    };
    if (!await prefs.setString(prefsKey, jsonEncode(payload))) {
      throw StateError('MCP 配置保存失败');
    }
    for (final id in oldEnvironmentIds.difference(environmentIds)) {
      await _secrets.delete(mcpEnvironmentSecretKey(id));
    }
    } finally {
      _saving = false;
    }
  }
}

/// MCP Server 仓库：CRUD、启用开关、策略覆盖；secret 只存 ref。
///
/// 生产： [PrefsMcpServerStorage] + [SecretStore]；测试可用 [MemoryMcpServerStorage]。
class McpServerRepository extends ChangeNotifier {
  McpServerRepository({required this._storage, SecretStore? secretStore})
    : _secrets = secretStore == null ? null : GuardedSecretStore(secretStore);

  final McpServerStorage _storage;
  final SecretStore? _secrets;
  bool get hasPendingSecretWrites => (_secrets is GuardedSecretStore && _secrets.isPending) || (_storage is PrefsMcpServerStorage && _storage.hasPendingWrites);
  final Map<String, int> _secretRevisions = {};
  final Map<String, Object> _probeTickets = {};
  final Map<String, int> _probeMutations = {};
  int _allProbeMutations = 0;

  Future<void> _withProbeMutation(
    String? id,
    Future<void> Function() action,
  ) async {
    if (id == null) {
      _allProbeMutations++;
      _probeTickets.clear();
    } else {
      _probeMutations[id] = (_probeMutations[id] ?? 0) + 1;
      _probeTickets.remove(id);
    }
    try {
      await action();
    } finally {
      if (id == null) {
        _allProbeMutations--;
        _probeTickets.clear();
      } else {
        final count = _probeMutations[id]! - 1;
        if (count == 0) {
          _probeMutations.remove(id);
        } else {
          _probeMutations[id] = count;
        }
        _probeTickets.remove(id);
      }
    }
  }

  String _probeConfig(McpServerConfig server) => jsonEncode([
    server.displayName,
    mcpAuthorizationFingerprint(server),
    server.stdioApproval,
    server.callTimeoutSeconds,
  ]);

  /// Repository-scoped ticket: shared across service/UI instances.
  Object? beginProbe(String id) {
    if (_allProbeMutations > 0 ||
        _probeMutations.containsKey(id) ||
        findById(id) == null) {
      return null;
    }
    final ticket = Object();
    _probeTickets[id] = ticket;
    return ticket;
  }

  bool isProbeCurrent(String id, Object ticket) =>
      identical(_probeTickets[id], ticket) && findById(id) != null;

  /// Patch only probe metadata, never credentials, command approval or policies.
  /// Unlike ordinary optimistic CRUD, completion awaits and propagates storage
  /// failure. A failed write must not leave an in-memory ready result.
  Future<bool> persistProbe(
    String id,
    Object ticket, {
    required McpProbeStatus status,
    List<McpToolDescriptor>? tools,
    int? atMs,
    String? error,
  }) async {
    var applied = false;
    final task = (_persistChain ?? Future<void>.value()).then((_) async {
      if (!isProbeCurrent(id, ticket)) return;
      final current = findById(id)!;
      final next = current.copyWith(
        probeStatus: status,
        toolsCache: tools == null ? null : List.unmodifiable(tools),
        lastProbeAtMs: atMs,
        lastError: error,
        clearLastError: error == null,
      );
      try {
        await _storage.save(
          McpServerStoreSnapshot(
            servers: [
              for (final s in _servers)
                if (s.id == id) next else s,
            ],
          ),
        );
        applied = isProbeCurrent(id, ticket);
        if (applied) {
          _servers = [
            for (final s in _servers)
              if (s.id == id) next else s,
          ];
          _lastError = null;
          notifyListeners();
        }
      } catch (e) {
        if (isProbeCurrent(id, ticket)) {
          _servers = [
            for (final s in _servers)
              if (s.id == id)
                current.copyWith(
                  probeStatus: McpProbeStatus.error,
                  lastError: '探测状态保存失败',
                )
              else
                s,
          ];
        }
        _lastError = '探测状态保存失败';
        notifyListeners();
        rethrow;
      }
    });
    // Keep the queue usable; the caller still receives this task's failure.
    _persistChain = task.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    await task;
    return applied;
  }

  int secretRevision(String id) => _secretRevisions[id] ?? 0;

  void _secretChanged(String id) {
    _probeTickets.remove(id);
    _secretRevisions[id] = secretRevision(id) + 1;
  }

  List<McpServerConfig> _servers = const [];
  bool _loaded = false;
  bool _loading = false;
  String? _lastError;

  bool get isLoaded => _loaded;
  bool get isLoading => _loading;
  String? get lastError => _lastError;

  List<McpServerConfig> get servers => List.unmodifiable(_servers);

  /// 已启用且可向模型暴露 tools 的 Server。
  List<McpServerConfig> get enabledServers => [
    for (final s in _servers)
      if (s.canExposeTools) s,
  ];

  /// 汇总已启用 Server 的 tools 缓存（供 chat 请求附带 tools[]）。
  List<McpToolDescriptor> get exposedTools {
    final out = <McpToolDescriptor>[];
    for (final s in enabledServers) {
      out.addAll(s.toolsCache);
    }
    return List.unmodifiable(out);
  }

  McpServerConfig? findById(String id) {
    for (final s in _servers) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<void> load() async {
    if (hasPendingSecretWrites) throw StateError('安全存储仍在处理中');
    if (_loading) return;
    _probeTickets.clear();
    _loading = true;
    _lastError = null;
    notifyListeners();
    try {
      final snap = await _storage.load();
      _servers = [
        for (final s in snap.servers)
          if (s.transport == McpTransport.stdio && !s.isStdioApproved)
            s.copyWith(enabled: false, clearStdioApproval: true)
          else
            s,
      ];
      _loaded = true;
    } catch (e) {
      _lastError = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    await _storage.save(McpServerStoreSnapshot(servers: _servers));
  }

  Future<void>? _persistChain;

  /// 内存已改后立刻通知；落盘串行排队，不阻塞返回。
  void _commitMemory() {
    _lastError = null;
    notifyListeners();
    _persistChain = (_persistChain ?? Future<void>.value()).then((_) async {
      try {
        await _persist();
      } catch (e) {
        _lastError = e.toString();
        notifyListeners();
      }
    });
  }

  /// 等待当前持久化队列；错误见 lastError。
  Future<void> waitForPersist() async {
    await (_persistChain ?? Future<void>.value());
  }

  /// 新建 Server；返回分配的 id。
  ///
  /// [transport] 默认 http；stdio 时用 [command]/[args]/[env]/[cwd]，
  /// [baseUrl] 可空。UI 层（桌面）负责用户确认命令后再调用。
  Future<String> add({
    required String displayName,
    String baseUrl = '',
    McpTransport transport = McpTransport.http,
    String? command,
    List<String> args = const [],
    Map<String, String> env = const {},
    String? cwd,
    McpAuthKind authKind = McpAuthKind.none,
    String? bearerToken,
    bool enabled = true,
    bool stdioConfirmed = false,
  }) async {
    final id = createId('mcp');
    String? secretRef;
    if (authKind == McpAuthKind.bearer) {
      secretRef = _secretKeyFor(id);
      final token = bearerToken?.trim() ?? '';
      if (token.isNotEmpty && _secrets != null) {
        await _secrets.write(secretRef, token);
      }
    }
    final cmd = command?.trim();
    final workDir = cwd?.trim();
    var server = McpServerConfig(
      id: id,
      displayName: displayName.trim().isEmpty ? '未命名 MCP' : displayName.trim(),
      transport: transport,
      baseUrl: baseUrl.trim(),
      command: (cmd == null || cmd.isEmpty) ? null : cmd,
      args: List<String>.from(args),
      env: Map<String, String>.from(env),
      cwd: (workDir == null || workDir.isEmpty) ? null : workDir,
      enabled: enabled,
      authKind: authKind,
      authSecretRef: secretRef,
    );
    if (transport == McpTransport.stdio) {
      server = server.copyWith(
        stdioApproval: stdioConfirmed ? mcpStdioFingerprint(server) : null,
        enabled: enabled && stdioConfirmed,
      );
    }
    _servers = [..._servers, server];
    _commitMemory();
    return id;
  }

  Future<void> update(
    McpServerConfig server, {
    bool stdioConfirmed = false,
  }) async {
    final i = _servers.indexWhere((s) => s.id == server.id);
    if (i < 0) return;
    if (server.transport == McpTransport.stdio) {
      final approved =
          stdioConfirmed ||
          (_servers[i].isStdioApproved &&
              mcpStdioFingerprint(_servers[i]) == mcpStdioFingerprint(server));
      server = server.copyWith(
        stdioApproval: approved ? mcpStdioFingerprint(server) : null,
        clearStdioApproval: !approved,
        enabled: server.enabled && approved,
      );
    } else {
      server = server.copyWith(clearStdioApproval: true);
    }
    if (_probeConfig(_servers[i]) != _probeConfig(server)) {
      _probeTickets.remove(server.id);
    }
    final next = List<McpServerConfig>.from(_servers);
    next[i] = server;
    _servers = next;
    _commitMemory();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final s = findById(id);
    if (s == null || s.enabled == enabled) return;
    await update(s.copyWith(enabled: enabled));
  }

  Future<void> setToolPolicyOverride(
    String serverId,
    String toolName,
    McpToolPolicyLevel? level,
  ) async {
    final s = findById(serverId);
    if (s == null) return;
    final name = toolName.trim();
    if (name.isEmpty) return;
    final map = Map<String, McpToolPolicyLevel>.from(s.toolPolicyOverrides);
    if (level == null) {
      map.remove(name);
    } else {
      map[name] = level;
    }
    await update(s.copyWith(toolPolicyOverrides: map));
  }

  /// 设置本 Server 默认授权；[level] 为 null 表示恢复「按副作用/元数据」。
  Future<void> setDefaultToolPolicy(
    String serverId,
    McpToolPolicyLevel? level,
  ) async {
    final s = findById(serverId);
    if (s == null) return;
    if (s.defaultToolPolicy == level) return;
    if (level == null) {
      await update(s.copyWith(clearDefaultToolPolicy: true));
    } else {
      await update(s.copyWith(defaultToolPolicy: level));
    }
  }

  Future<void> replaceToolsCache(
    String serverId,
    List<McpToolDescriptor> tools,
  ) async {
    final s = findById(serverId);
    if (s == null) return;
    await update(s.copyWith(toolsCache: List.unmodifiable(tools)));
  }

  /// 写入/更新 Bearer 明文到 SecretStore；配置侧只保留 ref。
  Future<void> writeBearerSecret(String serverId, String token) =>
      _withProbeMutation(serverId, () async {
        final s = findById(serverId);
        if (s == null) return;
        final ref = s.authSecretRef?.trim().isNotEmpty == true
            ? s.authSecretRef!.trim()
            : _secretKeyFor(serverId);
        _secretChanged(serverId);
        if (_secrets != null) {
          await _secrets.write(ref, token);
        }
        _probeTickets.remove(serverId);
        if (s.authSecretRef != ref || s.authKind != McpAuthKind.bearer) {
          await update(
            s.copyWith(authKind: McpAuthKind.bearer, authSecretRef: ref),
          );
        } else {
          _commitMemory();
        }
      });

  /// 是否已有 Bearer 明文（不回显内容；供 UI 掩码占位）。
  Future<bool> hasBearerSecret(String serverId) async {
    final s = findById(serverId);
    if (s == null || s.authKind != McpAuthKind.bearer) return false;
    final ref = s.authSecretRef?.trim() ?? '';
    if (ref.isEmpty || _secrets == null) return false;
    return _secrets.containsKey(ref);
  }

  /// 读取 Bearer 明文（仅备份含密钥等受控路径；禁止写入日志）。
  Future<String?> readBearerSecret(String serverId) async {
    final s = findById(serverId);
    if (s == null || s.authKind != McpAuthKind.bearer) return null;
    final ref = s.authSecretRef?.trim() ?? '';
    if (ref.isEmpty || _secrets == null) return null;
    final v = await _secrets.read(ref);
    final t = v?.trim() ?? '';
    return t.isEmpty ? null : t;
  }

  /// 清除 Bearer 密钥并改为 none（SET-MCP 鉴权切换）。
  Future<void> clearBearerSecret(String serverId) =>
      _withProbeMutation(serverId, () async {
        final s = findById(serverId);
        if (s == null) return;
        _secretChanged(serverId);
        final ref = s.authSecretRef;
        if (ref != null && ref.isNotEmpty && _secrets != null) {
          await _secrets.delete(ref);
        }
        if (s.authKind != McpAuthKind.none || s.authSecretRef != null) {
          await update(
            s.copyWith(authKind: McpAuthKind.none, clearAuthSecretRef: true),
          );
        }
      });

  Future<void> delete(String id) => _withProbeMutation(id, () async {
    _probeTickets.remove(id);
    final s = findById(id);
    if (s == null) return;
    await waitForPersist();
    final ref = s.authSecretRef;
    if (ref != null && ref.isNotEmpty && _secrets != null) {
      await _secrets.delete(ref);
    }
    _servers = [
      for (final e in _servers)
        if (e.id != id) e,
    ];
    _commitMemory();
    await waitForPersist();
    await _secrets?.delete(mcpEnvironmentSecretKey(id));
  });

  /// 整体替换 Server 列表（导入备份用）；不自动迁移密钥。
  Future<void> replaceAll(List<McpServerConfig> servers, {
    Set<String>? importedIds,
  }) async {
    if (hasPendingSecretWrites) throw StateError('安全存储仍在处理中');
    _probeTickets.clear();
    final next = [
      for (final s in servers)
        if (importedIds != null && !importedIds.contains(s.id)) s
        else if (s.transport == McpTransport.stdio)
          s.copyWith(enabled: false, clearStdioApproval: true)
        else s.copyWith(clearStdioApproval: true),
    ];
    final task = (_persistChain ?? Future<void>.value()).then((_) async {
      try {
        await _storage.save(McpServerStoreSnapshot(servers: next));
        _servers = next;
        _lastError = null;
        notifyListeners();
      } catch (_) {
        _lastError = 'MCP 保存未完成';
        notifyListeners();
        throw StateError('MCP 保存未完成');
      }
    });
    _persistChain = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    await task;
  }

  /// 清空全部 Server 元数据并删除对应 SecretStore 条目（SET-DATA 清提供商/全部）。
  Future<void> clearAllServers() => _withProbeMutation(null, () async {
    await clearAllSecrets();
    _servers = const [];
    _commitMemory();
    await waitForPersist();
  });

  /// 清密钥引用对应的 SecretStore 条目（对齐 SET-DATA 清密钥）。
  ///
  /// 保留 Server 元数据与 `authSecretRef`；[hasBearerSecret] 将为 false。
  Future<void> clearAllSecrets() => _withProbeMutation(null, () async {
    if (hasPendingSecretWrites) throw StateError('安全存储仍在处理中');
    _probeTickets.clear();
    await waitForPersist();
    for (final s in _servers) {
      _secretChanged(s.id);
      final ref = s.authSecretRef;
      if (ref != null && ref.isNotEmpty) {
        await _secrets?.delete(ref);
      }
    }
    final ids = _servers.map((s) => s.id).toList();
    _servers = [
      for (final s in _servers)
        s.copyWith(
          env: const {},
          clearStdioApproval: true,
          enabled: s.transport == McpTransport.stdio ? false : s.enabled,
        ),
    ];
    _commitMemory();
    await waitForPersist();
    for (final id in ids) {
      await _secrets?.delete(mcpEnvironmentSecretKey(id));
    }
  });

  static String _secretKeyFor(String serverId) => 'core.mcp.secret.$serverId';
}
