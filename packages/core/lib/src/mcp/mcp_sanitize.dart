import '../util/secret_sanitize.dart';

/// 日志 / 授权卡 / 轨迹摘要默认最大长度。
const int kMcpSummaryMaxLen = 200;

/// 截断 + 密钥脱敏（参数 / 结果 / 错误文案）。
///
/// **禁止**把 Bearer token 或完整密钥写入日志与会话轨迹摘要。
String mcpSanitizeSummary(String? raw, {int maxLen = kMcpSummaryMaxLen}) {
  var s = applySecretRedaction((raw ?? '').trim());
  if (s.isEmpty) return '';
  if (s.length > maxLen) {
    s = '${s.substring(0, maxLen)}…';
  }
  return s;
}

/// 从参数 JSON 生成授权卡摘要（截断脱敏；失败则原文截断）。
String mcpArgumentsSummary(String? argumentsJson, {int maxLen = kMcpSummaryMaxLen}) {
  final raw = (argumentsJson ?? '').trim();
  if (raw.isEmpty || raw == '{}') return '{}';
  return mcpSanitizeSummary(raw, maxLen: maxLen);
}
