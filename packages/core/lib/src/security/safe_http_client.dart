import 'package:http/http.dart' as http;

import 'url_safety.dart';

/// 默认最大重定向次数（与 `package:http` BaseRequest 默认一致）。
const int kDefaultMaxRedirects = 5;

/// 可自动跟随且需二次校验的 30x 状态码。
const Set<int> kRedirectStatusCodes = {301, 302, 303, 307, 308};

/// 创建默认出站 Client：对初始 URL 与每一次 redirect 目标做 [assertSafeHttpUrl]。
http.Client createSafeHttpClient({http.Client? inner}) {
  final owned = inner == null;
  return SafeRedirectHttpClient(
    inner ?? http.Client(),
    closeInner: owned,
  );
}

/// 是否应按 dart:io 规则自动跟随该 redirect。
///
/// - GET / HEAD：301 / 302 / 303 / 307 / 308
/// - POST：仅 303（跟随后改为 GET）
bool shouldFollowRedirect(String method, int statusCode) {
  if (!kRedirectStatusCodes.contains(statusCode)) return false;
  final m = method.toUpperCase();
  if (m == 'GET' || m == 'HEAD') return true;
  if (m == 'POST' && statusCode == 303) return true;
  return false;
}

/// 跟随 redirect 时使用的下一跳方法（303 且非 HEAD → GET）。
String redirectRequestMethod(String method, int statusCode) {
  final m = method.toUpperCase();
  if (statusCode == 303 && m != 'HEAD') return 'GET';
  return m;
}

/// 解析 Location（相对路径相对 [current] 解析）。
Uri resolveRedirectUri(Uri current, String location) {
  final trimmed = location.trim();
  if (trimmed.isEmpty) {
    throw const UrlSafetyException('重定向缺少 Location');
  }
  final resolved = current.resolve(trimmed);
  if (!resolved.hasScheme) {
    throw const UrlSafetyException('无效的重定向地址');
  }
  return resolved;
}

/// 校验 redirect 目标（与初始请求同一套硬拦规则）。
void assertSafeRedirectTarget(Uri url) {
  assertSafeHttpUrl(
    url,
    protocolMessage: '拒绝跟随到非 http/https 地址',
    blockedMessage: '拒绝跟随到云元数据或受保护地址',
  );
}

/// 包装 [inner]：关闭自动跟随，改为手动跟随并对每一跳做 url_safety 校验。
class SafeRedirectHttpClient extends http.BaseClient {
  SafeRedirectHttpClient(
    this._inner, {
    this.closeInner = false,
  });

  final http.Client _inner;
  final bool closeInner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    assertSafeHttpUrl(request.url);

    if (!request.followRedirects) {
      return _inner.send(request);
    }

    final maxRedirects =
        request.maxRedirects > 0 ? request.maxRedirects : kDefaultMaxRedirects;
    final persistentConnection = request.persistentConnection;
    final headers = Map<String, String>.from(request.headers);

    // 普通 Request 可重放 body；multipart / 流式仅在改为 GET/HEAD 时跟随。
    List<int>? bodyBytes;
    if (request is http.Request) {
      bodyBytes = List<int>.from(request.bodyBytes);
    }

    var method = request.method.toUpperCase();
    var url = request.url;
    request.followRedirects = false;
    var response = await _inner.send(request);
    var redirects = 0;

    while (shouldFollowRedirect(method, response.statusCode)) {
      if (redirects >= maxRedirects) {
        await response.stream.drain<void>();
        throw http.ClientException(
          'Redirect limit exceeded ($maxRedirects)',
          url,
        );
      }

      final location = _headerValue(response.headers, 'location');
      if (location == null || location.trim().isEmpty) {
        await response.stream.drain<void>();
        throw http.ClientException('Redirect response missing Location', url);
      }

      final nextUrl = resolveRedirectUri(url, location);
      try {
        assertSafeRedirectTarget(nextUrl);
      } on UrlSafetyException {
        await response.stream.drain<void>();
        rethrow;
      }

      await response.stream.drain<void>();
      method = redirectRequestMethod(method, response.statusCode);
      url = nextUrl;
      redirects += 1;

      final hop = http.Request(method, url)
        ..followRedirects = false
        ..maxRedirects = 0
        ..persistentConnection = persistentConnection
        ..headers.addAll(headers);
      if (bodyBytes != null && _methodMayHaveBody(method)) {
        hop.bodyBytes = bodyBytes;
      }
      response = await _inner.send(hop);
    }

    return response;
  }

  @override
  void close() {
    if (closeInner) {
      _inner.close();
    }
  }
}

bool _methodMayHaveBody(String method) {
  final m = method.toUpperCase();
  return m != 'GET' && m != 'HEAD';
}

String? _headerValue(Map<String, String> headers, String name) {
  final lower = name.toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == lower) return entry.value;
  }
  return null;
}
