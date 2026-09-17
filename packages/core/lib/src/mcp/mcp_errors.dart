/// MCP Client 可读异常（DESIGN §5.11 / §6）。
library;

/// 用户停止或编排取消。
class McpCancelledException implements Exception {
  const McpCancelledException([this.message = '已取消']);

  final String message;

  @override
  String toString() => message;
}

/// 超时。
class McpTimeoutException implements Exception {
  const McpTimeoutException([this.message = 'MCP 请求超时']);

  final String message;

  @override
  String toString() => message;
}

/// HTTP / 网络层失败（已映射文案，无密钥）。
class McpHttpException implements Exception {
  const McpHttpException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// JSON-RPC / 协议形状错误。
class McpProtocolException implements Exception {
  const McpProtocolException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// URL 不安全（包装 [UrlSafetyException] 文案）。
class McpUnsafeUrlException implements Exception {
  const McpUnsafeUrlException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// stdio 子进程启动 / 退出 / IO 失败。
class McpProcessException implements Exception {
  const McpProcessException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 是否为取消类异常。
bool isMcpCancelLike(Object? error) {
  if (error is McpCancelledException) return true;
  final msg = error?.toString() ?? '';
  return RegExp(r'cancel+ed|aborted|已取消|ClientException.*closed',
          caseSensitive: false)
      .hasMatch(msg);
}
