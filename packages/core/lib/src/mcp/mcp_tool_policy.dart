import 'mcp_models.dart';

/// 会话内 `confirm_once` 已授权集合（serverId + toolName）。
class McpSessionToolGrants {
  McpSessionToolGrants([Set<String>? initial])
      : _keys = Set<String>.from(initial ?? const {});

  final Set<String> _keys;

  static String key(String serverId, String toolName) =>
      '${serverId.trim()}::${toolName.trim()}';

  bool hasGrant(String serverId, String toolName) =>
      _keys.contains(key(serverId, toolName));

  void grant(String serverId, String toolName) {
    _keys.add(key(serverId, toolName));
  }

  void revoke(String serverId, String toolName) {
    _keys.remove(key(serverId, toolName));
  }

  void clear() => _keys.clear();

  Set<String> get debugKeys => Set.unmodifiable(_keys);
}

/// 分级授权解析（DESIGN §5.11.4）。
///
/// 优先级：用户覆盖 > tool 元数据建议 > 客户端默认
/// （unknown/write → [confirmAlways]；明确 read → 建议 [autoAllow]）。
class McpToolPolicyResolver {
  const McpToolPolicyResolver();

  /// 解析最终策略级别（不含 confirm_once 会话降级）。
  ///
  /// 优先级：单 tool 覆盖 > Server [defaultToolPolicy] > tool 元数据建议 >
  /// 客户端按副作用默认。
  McpToolPolicyLevel resolve({
    required McpServerConfig server,
    required McpToolDescriptor tool,
    Map<String, McpToolPolicyLevel>? overrides,
  }) {
    final map = overrides ?? server.toolPolicyOverrides;
    final user = map[tool.name];
    if (user != null) return user;

    if (server.defaultToolPolicy != null) return server.defaultToolPolicy!;

    if (tool.suggestedPolicy != null) return tool.suggestedPolicy!;

    return defaultLevelFor(tool.sideEffect);
  }

  /// 结合会话 grants：若级别为 [confirmOnce] 且本会话已授权 → [autoAllow]。
  McpToolPolicyLevel resolveEffective({
    required McpServerConfig server,
    required McpToolDescriptor tool,
    McpSessionToolGrants? sessionGrants,
    Map<String, McpToolPolicyLevel>? overrides,
  }) {
    final level = resolve(server: server, tool: tool, overrides: overrides);
    if (level == McpToolPolicyLevel.confirmOnce &&
        sessionGrants != null &&
        sessionGrants.hasGrant(server.id, tool.name)) {
      return McpToolPolicyLevel.autoAllow;
    }
    return level;
  }

  /// 客户端默认：明确 read → autoAllow；其余 → confirmAlways。
  static McpToolPolicyLevel defaultLevelFor(McpToolSideEffect sideEffect) {
    switch (sideEffect) {
      case McpToolSideEffect.read:
        return McpToolPolicyLevel.autoAllow;
      case McpToolSideEffect.write:
      case McpToolSideEffect.unknown:
        return McpToolPolicyLevel.confirmAlways;
    }
  }
}
