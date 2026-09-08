/// 日志 / 错误文案共用的密钥脱敏（不截断长度）。
///
/// 覆盖：Authorization、常见 header / 赋值形态、URL query·fragment 敏感参数、
/// 常见厂商 token 前缀。query 参数要求 `?`/`&`/`#` 边界；裸 `key=`/`token=`
/// 不在赋值形态里通配，降低误伤普通英文。
String applySecretRedaction(String text) {
  var s = text;

  // Authorization: [Scheme ]凭证
  s = s.replaceAllMapped(
    RegExp(
      r'(Authorization\s*:\s*)((?:Bearer|Basic|Digest)\s+)?(\S+)',
      caseSensitive: false,
    ),
    (m) => '${m[1]}${m[2] ?? ''}***',
  );

  // 独立 Bearer 片段（无 Authorization 前缀时）
  s = s.replaceAllMapped(
    RegExp(r'Bearer\s+[A-Za-z0-9._\-+=/]+', caseSensitive: false),
    (_) => 'Bearer ***',
  );

  // Header / 赋值：x-api-key、api_key、api-key、apiKey
  // 三引号 raw，避免 ["'] 拆坏 \s
  s = s.replaceAllMapped(
    RegExp(
      r'''((?:x-)?api[_-]?key["']?\s*[:=]\s*["']?)([^\s&#"'<>]+)''',
      caseSensitive: false,
    ),
    (m) => '${m[1]}***',
  );

  // 赋值：access_token / refresh_token / client_secret / password / secret
  // （不含裸 token= / key=，那些只在 query 边界处理）
  s = s.replaceAllMapped(
    RegExp(
      r'''\b((?:access|refresh)[_-]?token|client[_-]?secret|password|secret)'''
      r'''(["']?\s*[:=]\s*["']?)([^\s&#"'<>]+)''',
      caseSensitive: false,
    ),
    (m) => '${m[1]}${m[2]}***',
  );

  // URL query / fragment 敏感参数（要求 ? & # 前缀）
  s = s.replaceAllMapped(
    RegExp(
      r'([?&#](?:api[_-]?key|access[_-]?token|refresh[_-]?token|'
      r'client[_-]?secret|password|secret|token|key)=)([^&#\s]*)',
      caseSensitive: false,
    ),
    (m) => '${m[1]}***',
  );

  // 常见厂商长 token 前缀
  s = s.replaceAllMapped(
    RegExp(r'\bsk-[A-Za-z0-9_-]{10,}\b'),
    (_) => '***',
  );
  s = s.replaceAllMapped(
    RegExp(r'\bxai-[A-Za-z0-9_-]{10,}\b'),
    (_) => '***',
  );
  s = s.replaceAllMapped(
    RegExp(r'\bgsk_[A-Za-z0-9_-]{10,}\b'),
    (_) => '***',
  );
  // Google API key 常见前缀
  s = s.replaceAllMapped(
    RegExp(r'\bAIza[A-Za-z0-9_-]{20,}\b'),
    (_) => '***',
  );

  return s;
}
