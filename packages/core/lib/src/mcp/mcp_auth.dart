import '../provider/secret_store.dart';
import 'mcp_models.dart';

/// MCP 出站鉴权：为 HTTP/SSE 请求提供 headers（DESIGN §5.11 · Q7）。
///
/// 密钥经 [SecretStore] 或回调读取；禁止硬编码 token。
abstract class McpAuthProvider {
  McpAuthKind get kind;

  /// 返回需附加的请求头（如 `Authorization`）；无鉴权返回空 map。
  Future<Map<String, String>> headers();
}

/// 无鉴权。
class NoneMcpAuth implements McpAuthProvider {
  const NoneMcpAuth();

  @override
  McpAuthKind get kind => McpAuthKind.none;

  @override
  Future<Map<String, String>> headers() async => const {};
}

/// Bearer Token：从 [SecretStore] 或回调读取。
class BearerMcpAuth implements McpAuthProvider {
  /// 从 [SecretStore] 按 [secretRef] 读取。
  BearerMcpAuth({
    required SecretStore secretStore,
    required this.secretRef,
    this.headerName = 'Authorization',
    this.scheme = 'Bearer',
  }) : _loadToken = (() => secretStore.read(secretRef));

  /// 直接用回调取 token（测试或上层已解析好密钥时）。
  BearerMcpAuth.fromTokenLoader({
    required this._loadToken,
    this.secretRef = '',
    this.headerName = 'Authorization',
    this.scheme = 'Bearer',
  });

  final Future<String?> Function() _loadToken;

  /// [SecretStore] 键；[fromTokenLoader] 时可为空。
  final String secretRef;
  final String headerName;
  final String scheme;

  @override
  McpAuthKind get kind => McpAuthKind.bearer;

  @override
  Future<Map<String, String>> headers() async {
    final token = await _loadToken();
    final t = token?.trim() ?? '';
    if (t.isEmpty) {
      throw StateError('MCP Bearer 密钥缺失（ref: $secretRef）');
    }
    final value = scheme.isEmpty ? t : '$scheme $t';
    return {headerName: value};
  }
}

/// OAuth 占位（P6 不做；仅预留 [McpAuthKind.oauth]）。
class OAuthMcpAuth implements McpAuthProvider {
  const OAuthMcpAuth();

  @override
  McpAuthKind get kind => McpAuthKind.oauth;

  @override
  Future<Map<String, String>> headers() {
    throw UnimplementedError('MCP OAuth 鉴权本期不做（DESIGN §5.11.9 / Q7）');
  }
}

/// 按 [McpServerConfig.authKind] 构造鉴权提供者。
McpAuthProvider createMcpAuthProvider({
  required McpServerConfig server,
  required SecretStore secretStore,
}) {
  switch (server.authKind) {
    case McpAuthKind.none:
      return const NoneMcpAuth();
    case McpAuthKind.bearer:
      final ref = server.authSecretRef?.trim() ?? '';
      if (ref.isEmpty) {
        throw ArgumentError('bearer 鉴权需要 authSecretRef');
      }
      return BearerMcpAuth(secretStore: secretStore, secretRef: ref);
    case McpAuthKind.oauth:
      return const OAuthMcpAuth();
  }
}
