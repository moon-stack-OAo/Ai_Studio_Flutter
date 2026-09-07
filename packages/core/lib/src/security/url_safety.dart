/// 出站 URL 安全策略（对齐现网 `urlSafety.js` / `url_safety.rs`）。
///
/// 硬拦：云元数据 / 链路本地 / 明显 SSRF 靶点。
/// 放行：localhost、RFC1918（产品需支持本地/内网中转）。
library;

/// 危险 host 黑名单（不含 127.0.0.1 / RFC1918）。
const Set<String> kBlockedFetchHosts = {
  '169.254.169.254',
  'metadata.google.internal',
  'metadata.google',
  'metadata',
  'kubernetes.default',
  'kubernetes.default.svc',
  // AWS IMDS IPv6
  'fd00:ec2::254',
};

/// URL 安全校验失败。
class UrlSafetyException implements Exception {
  const UrlSafetyException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 规范化 hostname：小写、去方括号、去尾点。
String normalizeHostname(String hostname) {
  return hostname
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'^\[|\]$'), '')
      .replaceAll(RegExp(r'\.$'), '');
}

/// 解析 IPv4 映射的 IPv6（`::ffff:a.b.c.d` 或 `::ffff:xxxx:yyyy`）。
String? extractIpv4Mapped(String host) {
  final dotted = RegExp(r'^::ffff:(\d{1,3}(?:\.\d{1,3}){3})$', caseSensitive: false)
      .firstMatch(host);
  if (dotted != null) return dotted.group(1);

  final hex = RegExp(r'^::ffff:([0-9a-f]{1,4}):([0-9a-f]{1,4})$', caseSensitive: false)
      .firstMatch(host);
  if (hex == null) return null;
  final hi = int.tryParse(hex.group(1)!, radix: 16);
  final lo = int.tryParse(hex.group(2)!, radix: 16);
  if (hi == null || lo == null) return null;
  return '${(hi >> 8) & 255}.${hi & 255}.${(lo >> 8) & 255}.${lo & 255}';
}

bool _isDottedIpv4(String host) =>
    RegExp(r'^\d{1,3}(?:\.\d{1,3}){3}$').hasMatch(host);

bool _isLoopbackHost(String host) {
  if (host == 'localhost' || host == '127.0.0.1') return true;
  if (host.startsWith('127.')) return true;
  return false;
}

bool _isPrivateIpv4(String host) {
  if (!_isDottedIpv4(host)) return false;
  final parts = host.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((n) => n == null || n < 0 || n > 255)) {
    return false;
  }
  final a = parts[0]!;
  final b = parts[1]!;
  if (a == 10) return true;
  if (a == 192 && b == 168) return true;
  if (a == 172 && b >= 16 && b <= 31) return true;
  return false;
}

/// 危险 host（硬拦）。不含 127.0.0.1 / RFC1918。
bool isBlockedFetchHost(String hostname) {
  final host = normalizeHostname(hostname);
  if (host.isEmpty) return true;
  if (kBlockedFetchHosts.contains(host)) return true;
  if (host.startsWith('169.254.')) return true;
  if (host == '0.0.0.0' || host == '::' || host == '::1') return true;

  final mapped = extractIpv4Mapped(host);
  if (mapped != null &&
      (mapped == '169.254.169.254' || mapped.startsWith('169.254.'))) {
    return true;
  }
  return false;
}

/// 校验已解析的 http(s) [url]。
void assertSafeHttpUrl(
  Uri url, {
  String protocolMessage = '仅允许 http/https 请求',
  String blockedMessage = '拒绝访问云元数据或受保护地址',
}) {
  final scheme = url.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    throw UrlSafetyException(protocolMessage);
  }
  if (isBlockedFetchHost(url.host)) {
    throw UrlSafetyException(blockedMessage);
  }
}

/// 拒绝明显危险出站目标。
///
/// 相对路径、`blob:`、`data:` 放行（与现网 `assertSafeFetchUrl` 一致）。
void assertSafeFetchUrl(Object? input) {
  final raw = _resolveRequestUrl(input);
  if (raw.isEmpty ||
      raw.startsWith('/') ||
      raw.startsWith('blob:') ||
      raw.startsWith('data:')) {
    return;
  }
  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.hasScheme) {
    throw const UrlSafetyException('无效的请求地址');
  }
  assertSafeHttpUrl(uri);
}

String _resolveRequestUrl(Object? input) {
  if (input == null) return '';
  if (input is Uri) return input.toString();
  return input.toString().trim();
}

/// 非公网 / 明文 http 的风险提示（warn 级，不硬拦）。
///
/// 返回 `null` 表示无需提示。
String? warnUnsafeUrl(Object? input) {
  late final Uri url;
  try {
    if (input is Uri) {
      url = input;
    } else {
      final raw = (input?.toString() ?? '').trim();
      if (raw.isEmpty ||
          raw.startsWith('/') ||
          raw.startsWith('blob:') ||
          raw.startsWith('data:')) {
        return null;
      }
      final parsed = Uri.tryParse(raw);
      if (parsed == null || !parsed.hasScheme) return null;
      url = parsed;
    }
  } catch (_) {
    return null;
  }

  final scheme = url.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;

  final host = normalizeHostname(url.host);
  final reasons = <String>[];

  if (scheme == 'http') {
    reasons.add('使用明文 HTTP，密钥可能被窃听');
  }
  if (_isLoopbackHost(host)) {
    reasons.add('指向本机地址，仅适合本地中转调试');
  } else if (_isPrivateIpv4(host)) {
    reasons.add('指向私有网段（RFC1918），请确认中转可信');
  }

  if (reasons.isEmpty) return null;
  return '安全提示：${reasons.join('；')}';
}
