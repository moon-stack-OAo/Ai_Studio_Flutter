/// 对话 / SSE 相关错误与文案（中文、脱敏，禁止泄露 apiKey）。

const int _maxErrorTextLen = 240;

/// 上传内容过大（HTTP 413）统一提示。
const String http413Hint =
    '上传内容过大（HTTP 413）。请换更小的参考图，或已自动压缩仍失败则换图重试。';

/// 用户主动取消流式请求。
class ChatAbortException implements Exception {
  const ChatAbortException([this.message = '已取消']);

  final String message;

  @override
  String toString() => message;
}

/// 上游 / 网络业务错误（已映射为可读中文）。
class ChatApiException implements Exception {
  const ChatApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

bool isAbortLike(Object? error) {
  if (error is ChatAbortException) return true;
  if (error is ChatApiException && error.message == '已取消') return true;
  final msg = error is Exception
      ? error.toString()
      : (error?.toString() ?? '');
  return RegExp(r'cancel+ed|aborted|已取消|ClientException.*closed',
          caseSensitive: false)
      .hasMatch(msg);
}

ChatAbortException toAbortError() => const ChatAbortException();

/// 脱敏密钥 / 截断过长文案。
String sanitizeErrorText(String? text, [String fallback = '']) {
  var s = (text ?? '').trim();
  if (s.isEmpty ||
      s == 'undefined' ||
      s == '[object Object]' ||
      s == 'Error') {
    return fallback;
  }
  if ((s.startsWith('{') &&
          RegExp(r'"config"\s*:|"headers"\s*:|"stack"\s*:').hasMatch(s)) ||
      RegExp(r'Bearer\s+sk-|x-api-key', caseSensitive: false).hasMatch(s)) {
    return fallback.isNotEmpty ? fallback : '请求失败，请稍后重试';
  }
  s = s
      .replaceAllMapped(
        RegExp(r'Bearer\s+[A-Za-z0-9._\-]+', caseSensitive: false),
        (_) => 'Bearer ***',
      )
      .replaceAllMapped(
        RegExp(r'(api[_-]?key["'']?\s*[:=]\s*["'']?)[A-Za-z0-9._\-]+',
            caseSensitive: false),
        (m) => '${m[1]}***',
      )
      .replaceAllMapped(
        RegExp(r'\bsk-[A-Za-z0-9_-]{10,}\b'),
        (_) => '***',
      )
      .replaceAllMapped(
        RegExp(r'\bxai-[A-Za-z0-9_-]{10,}\b'),
        (_) => '***',
      )
      .replaceAllMapped(
        RegExp(r'\bgsk_[A-Za-z0-9_-]{10,}\b'),
        (_) => '***',
      );
  if (s.length > _maxErrorTextLen) {
    s = '${s.substring(0, _maxErrorTextLen)}…';
  }
  return s;
}

/// 从上游 JSON 提取错误信息。
String extractApiErrorMessage(Object? data) {
  if (data == null) return '';
  if (data is String) return data.trim();
  if (data is! Map) return data.toString();
  if (data.containsKey('config') ||
      data.containsKey('headers') ||
      data.containsKey('request') ||
      data.containsKey('stack')) {
    return '';
  }
  final error = data['error'];
  if (error is String) return error;
  if (error is Map) {
    final msg = error['message'];
    if (msg is String) return msg;
    final code = error['code'];
    if (code is String) return code;
  }
  final message = data['message'];
  if (message is String) return message;
  final msg = data['msg'];
  if (msg is String) return msg;
  final detail = data['detail'];
  if (detail is String) return detail;
  if (detail is List && detail.isNotEmpty) {
    final first = detail.first;
    if (first is Map && first['msg'] != null) {
      return first['msg'].toString();
    }
  }
  return '';
}

/// 是否为 HTTP 413 / payload too large。
bool isHttp413Error(Object? error) {
  if (error is ChatApiException) {
    if (error.statusCode == 413) return true;
    return RegExp(
      r'HTTP\s*413|payload too large|request entity too large|上传内容过大',
      caseSensitive: false,
    ).hasMatch(error.message);
  }
  final msg = error?.toString() ?? '';
  return RegExp(
    r'HTTP\s*413|payload too large|request entity too large|上传内容过大',
    caseSensitive: false,
  ).hasMatch(msg);
}

/// HTTP 状态 → 中文提示。
String httpStatusErrorMessage(int? status, [String bodyMessage = '']) {
  if (status == 413) return http413Hint;
  final fromBody = sanitizeErrorText(bodyMessage, '');
  final looks413 = RegExp(
    r'^HTTP\s*413\b|payload too large|request entity too large',
    caseSensitive: false,
  ).hasMatch(fromBody);
  if (fromBody.isNotEmpty && !looks413) {
    if (status == 401 || status == 403) return fromBody;
    if (status == 404) return fromBody;
    if (status == 429) return fromBody;
    if (status == 400) return fromBody;
    if (status != null && status >= 500) return fromBody;
    return fromBody;
  }
  if (looks413) return http413Hint;
  if (status == 401 || status == 403) {
    return '鉴权失败，请检查 API Key';
  }
  if (status == 404) {
    return '接口不存在（404），请核对 Base URL 是否含 /v1 等路径';
  }
  if (status == 429) {
    return '请求过于频繁，请稍后重试';
  }
  if (status == 400) {
    return fromBody.isNotEmpty ? fromBody : '请求参数有误（400）';
  }
  if (status != null && status >= 500) {
    return fromBody.isNotEmpty ? fromBody : '上游服务异常（$status）';
  }
  if (fromBody.isNotEmpty) return fromBody;
  if (status != null) return 'HTTP $status';
  return '';
}

String describeNetworkError(Object error) {
  if (isAbortLike(error)) return '已取消';
  final raw = error.toString();
  if (RegExp(r'timeout|TimeoutException|timed?\s*out', caseSensitive: false)
      .hasMatch(raw)) {
    return '请求超时，请稍后重试或增大超时时间';
  }
  if (RegExp(r'SocketException|Failed host lookup|Connection refused|'
          r'Network is unreachable|Connection reset',
          caseSensitive: false)
      .hasMatch(raw)) {
    return '网络连接失败，请检查网络或 Base URL';
  }
  final cleaned = sanitizeErrorText(raw, '');
  return cleaned.isNotEmpty ? cleaned : '网络请求失败，请稍后重试';
}

String toChatErrorMessage(Object? error, [String fallback = '未知错误']) {
  if (error == null) return fallback;
  if (error is ChatAbortException) return error.message;
  if (error is ChatApiException) {
    return sanitizeErrorText(error.message, fallback);
  }
  if (error is String) {
    return sanitizeErrorText(error, fallback);
  }
  return sanitizeErrorText(describeNetworkError(error), fallback);
}
