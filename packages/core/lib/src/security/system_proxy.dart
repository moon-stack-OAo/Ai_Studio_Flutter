import 'dart:io';

/// Windows「Internet 设置」里的代理（IE / WinINET）。
class WindowsProxySettings {
  const WindowsProxySettings({
    required this.enabled,
    required this.proxyServer,
    this.proxyOverride = '',
  });

  final bool enabled;
  final String proxyServer;
  final String proxyOverride;
}

/// 从环境变量读取代理值（小写优先，与 Dart [HttpClient.findProxyFromEnvironment] 一致）。
String? proxyEnvValue(Map<String, String> environment, String name) {
  final lower = name.toLowerCase();
  final upper = name.toUpperCase();
  final a = environment[lower];
  if (a != null && a.trim().isNotEmpty) return a.trim();
  final b = environment[upper];
  if (b != null && b.trim().isNotEmpty) return b.trim();
  return null;
}

bool environmentHasHttpProxy(Map<String, String> environment) {
  return proxyEnvValue(environment, 'http_proxy') != null ||
      proxyEnvValue(environment, 'https_proxy') != null ||
      proxyEnvValue(environment, 'all_proxy') != null;
}

/// [ProxyOverride] 是否命中 [host]（支持 `*`、`<local>`、精确匹配）。
bool hostMatchesProxyOverride(String host, String proxyOverride) {
  final hostNorm = normalizeProxyHost(host);
  if (hostNorm.isEmpty) return false;
  for (final raw in proxyOverride.split(';')) {
    final pattern = raw.trim().toLowerCase();
    if (pattern.isEmpty) continue;
    if (pattern == '<local>') {
      if (!hostNorm.contains('.')) return true;
      continue;
    }
    if (pattern.contains('*')) {
      final escaped = RegExp.escape(pattern).replaceAll(r'\*', '.*');
      if (RegExp('^$escaped\$').hasMatch(hostNorm)) return true;
      continue;
    }
    if (hostNorm == pattern) return true;
  }
  return false;
}

String normalizeProxyHost(String host) {
  return host
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'^\[|\]$'), '')
      .replaceAll(RegExp(r'\.$'), '');
}

/// 从 Windows `ProxyServer` 选出适用于 [scheme] 的 `host:port`。
///
/// 支持：
/// - `127.0.0.1:7897`
/// - `http=127.0.0.1:7897;https=127.0.0.1:7897`
String? pickWindowsProxyServer(String proxyServer, String scheme) {
  final raw = proxyServer.trim();
  if (raw.isEmpty) return null;
  if (!raw.contains('=')) {
    return _stripProxyScheme(raw);
  }
  final map = <String, String>{};
  for (final part in raw.split(';')) {
    final idx = part.indexOf('=');
    if (idx <= 0) continue;
    final key = part.substring(0, idx).trim().toLowerCase();
    final value = _stripProxyScheme(part.substring(idx + 1).trim());
    if (key.isEmpty || value.isEmpty) continue;
    map[key] = value;
  }
  final want = scheme.toLowerCase() == 'https' ? 'https' : 'http';
  final preferred = map[want] ?? map['http'] ?? map['https'] ?? map['socks'];
  if (preferred != null) return preferred;
  return map.isEmpty ? null : map.values.first;
}

String _stripProxyScheme(String server) {
  return server
      .trim()
      .replaceFirst(RegExp(r'^(https?|socks5?)://', caseSensitive: false), '');
}

/// 解析 PAC 风格代理指令：`DIRECT` / `PROXY host:port`。
///
/// 优先级：
/// 1. 环境变量 `http(s)_proxy` / `all_proxy`（走 Dart 标准解析，含 `no_proxy`）
/// 2. Windows 系统代理（注册表 Internet Settings）
/// 3. `DIRECT`
String resolveHttpProxy(
  Uri url, {
  Map<String, String>? environment,
  WindowsProxySettings? windows,
}) {
  final env = environment ?? Platform.environment;
  if (environmentHasHttpProxy(env)) {
    return HttpClient.findProxyFromEnvironment(url, environment: env);
  }

  final win = windows;
  if (win != null && win.enabled) {
    final host = normalizeProxyHost(url.host);
    if (hostMatchesProxyOverride(host, win.proxyOverride)) {
      return 'DIRECT';
    }
    final server = pickWindowsProxyServer(win.proxyServer, url.scheme);
    if (server != null && server.isNotEmpty) {
      return 'PROXY $server';
    }
  }
  return 'DIRECT';
}

/// 读取当前用户 Windows Internet 代理设置；非 Windows 或失败返回 null。
WindowsProxySettings? readWindowsInternetProxySettings() {
  if (!Platform.isWindows) return null;
  try {
    final result = Process.runSync(
      'reg',
      const [
        'query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
      ],
      runInShell: false,
    );
    if (result.exitCode != 0) return null;
    final out = result.stdout?.toString() ?? '';
    if (out.isEmpty) return null;

    final enable = _regDword(out, 'ProxyEnable') ?? 0;
    final server = _regSz(out, 'ProxyServer') ?? '';
    final override = _regSz(out, 'ProxyOverride') ?? '';
    return WindowsProxySettings(
      enabled: enable != 0,
      proxyServer: server,
      proxyOverride: override,
    );
  } catch (_) {
    return null;
  }
}

int? _regDword(String regOutput, String name) {
  final re = RegExp(
    '$name\\s+REG_DWORD\\s+0x([0-9a-fA-F]+)',
    multiLine: true,
  );
  final m = re.firstMatch(regOutput);
  if (m == null) return null;
  return int.tryParse(m.group(1)!, radix: 16);
}

String? _regSz(String regOutput, String name) {
  final re = RegExp(
    '$name\\s+REG_SZ\\s+(.+)\$',
    multiLine: true,
  );
  final m = re.firstMatch(regOutput);
  if (m == null) return null;
  return m.group(1)!.trimRight();
}

/// 创建已绑定 [resolveHttpProxy] 的 [HttpClient]（创建时快照环境变量与 Windows 代理）。
HttpClient createProxyAwareHttpClient({
  Map<String, String>? environment,
  WindowsProxySettings? windows,
  bool readWindowsProxy = true,
}) {
  final env = Map<String, String>.from(environment ?? Platform.environment);
  final win = windows ??
      (readWindowsProxy && !environmentHasHttpProxy(env)
          ? readWindowsInternetProxySettings()
          : null);
  final client = HttpClient();
  client.findProxy = (url) => resolveHttpProxy(
        url,
        environment: env,
        windows: win,
      );
  return client;
}
