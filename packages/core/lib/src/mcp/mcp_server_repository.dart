import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../provider/secret_store.dart';
import '../util/id.dart';
import 'mcp_models.dart';

/// MCP Server 列表持久化快照（元数据；密钥仅存 ref）。
class McpServerStoreSnapshot {
  const McpServerStoreSnapshot({
    required this.servers,
  });

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
  PrefsMcpServerStorage({SharedPreferences? prefs}) : _prefsOverride = prefs;

  static const prefsKey = 'core.mcp_servers.v1';

  final SharedPreferences? _prefsOverride;
  SharedPreferences? _prefs;

  Future<SharedPreferences> _ensurePrefs() async {
    return _prefs ??= _prefsOverride ?? await SharedPreferences.getInstance();
  }

  @override
  Future<McpServerStoreSnapshot> load() async {
    final prefs = await _ensurePrefs();
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) {
      return const McpServerStoreSnapshot(servers: []);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const McpServerStoreSnapshot(servers: []);
      }
      final listRaw = decoded['servers'];
      final items = <McpServerConfig>[];
      if (listRaw is List) {
        for (final entry in listRaw) {
          if (entry is! Map) continue;
          items.add(
            McpServerConfig.fromJson(Map<String, dynamic>.from(entry)),
          );
        }
      }
      return McpServerStoreSnapshot(servers: items);
    } catch (_) {
      return const McpServerStoreSnapshot(servers: []);
    }
  }

  @override
  Future<void> save(McpServerStoreSnapshot snapshot) async {
    final prefs = await _ensurePrefs();
    final payload = {
      'servers': [
        for (final s in snapshot.servers) s.toJsonMeta(),
      ],
    };
    await prefs.setString(prefsKey, jsonEncode(payload));
  }
}

/// MCP Server 仓库：CRUD、启用开关、策略覆盖；secret 只存 ref。
///
/// 生产： [PrefsMcpServerStorage] + [SecretStore]；测试可用 [MemoryMcpServerStorage]。
class McpServerRepository extends ChangeNotifier {
  McpServerRepository({
    required this._storage,
    SecretStore? secretStore,
  }) : _secrets = secretStore;

  final McpServerStorage _storage;
  final SecretStore? _secrets;

  List<McpServerConfig> _servers = const [];
  bool _loaded = false;
  bool _loading = false;
  String? _lastError;

  bool get isLoaded => _loaded;
  bool get isLoading => _loading;
  String? get lastError => _lastError;

  List<McpServerConfig> get servers => List.unmodifiable(_servers);

  /// 已启用且可向模型暴露 tools 的 Server。
  List<McpServerConfig> get enabledServers =>
      [for (final s in _servers) if (s.canExposeTools) s];

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
    if (_loading) return;
    _loading = true;
    _lastError = null;
    notifyListeners();
    try {
      final snap = await _storage.load();
      _servers = List<McpServerConfig>.from(snap.servers);
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

  @visibleForTesting
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
    final server = McpServerConfig(
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
    _servers = [..._servers, server];
    _commitMemory();
    return id;
  }

  Future<void> update(McpServerConfig server) async {
    final i = _servers.indexWhere((s) => s.id == server.id);
    if (i < 0) return;
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
  Future<void> writeBearerSecret(String serverId, String token) async {
    final s = findById(serverId);
    if (s == null) return;
    final ref = s.authSecretRef?.trim().isNotEmpty == true
        ? s.authSecretRef!.trim()
        : _secretKeyFor(serverId);
    if (_secrets != null) {
      await _secrets.write(ref, token);
    }
    if (s.authSecretRef != ref || s.authKind != McpAuthKind.bearer) {
      await update(
        s.copyWith(authKind: McpAuthKind.bearer, authSecretRef: ref),
      );
    }
  }

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
  Future<void> clearBearerSecret(String serverId) async {
    final s = findById(serverId);
    if (s == null) return;
    final ref = s.authSecretRef;
    if (ref != null && ref.isNotEmpty && _secrets != null) {
      await _secrets.delete(ref);
    }
    if (s.authKind != McpAuthKind.none || s.authSecretRef != null) {
      await update(
        s.copyWith(
          authKind: McpAuthKind.none,
          clearAuthSecretRef: true,
        ),
      );
    }
  }

  Future<void> delete(String id) async {
    final s = findById(id);
    if (s == null) return;
    final ref = s.authSecretRef;
    if (ref != null && ref.isNotEmpty && _secrets != null) {
      await _secrets.delete(ref);
    }
    _servers = [for (final e in _servers) if (e.id != id) e];
    _commitMemory();
  }

  /// 整体替换 Server 列表（导入备份用）；不自动迁移密钥。
  Future<void> replaceAll(List<McpServerConfig> servers) async {
    _servers = List<McpServerConfig>.from(servers);
    _commitMemory();
    await waitForPersist();
  }

  /// 清空全部 Server 元数据并删除对应 SecretStore 条目（SET-DATA 清提供商/全部）。
  Future<void> clearAllServers() async {
    await clearAllSecrets();
    _servers = const [];
    _commitMemory();
    await waitForPersist();
  }

  /// 清密钥引用对应的 SecretStore 条目（对齐 SET-DATA 清密钥）。
  ///
  /// 保留 Server 元数据与 `authSecretRef`；[hasBearerSecret] 将为 false。
  Future<void> clearAllSecrets() async {
    if (_secrets == null) return;
    for (final s in _servers) {
      final ref = s.authSecretRef;
      if (ref != null && ref.isNotEmpty) {
        await _secrets.delete(ref);
      }
    }
  }

  static String _secretKeyFor(String serverId) => 'core.mcp.secret.$serverId';
}
