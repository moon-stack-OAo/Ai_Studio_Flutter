import '../chat/chat_errors.dart';

/// VID-PLAYER 播放失败 / 弱网统一文案（纯字符串，无 UI）。
///
/// 主句中文、简短可行动；弱网/远端可附极短原因，避免整段底层英文。
abstract final class VideoPlaybackErrors {
  static const noAddress = '没有可播放的视频地址';
  static const memoryOnly = '内存视频请先另存或系统打开';
  static const localMissing = '本地文件不存在';

  /// `Player.open` / 初始化异常。
  static String initFailed(Object error, {bool isRemote = false}) {
    final reason = briefReason(error);
    if (isRemote || looksNetwork(error.toString())) {
      return reason.isEmpty
          ? '无法加载远端视频，请检查网络后重试'
          : '无法加载远端视频，请检查网络后重试（$reason）';
    }
    return reason.isEmpty ? '播放器初始化失败，请重试' : '播放器初始化失败：$reason';
  }

  /// `player.stream.error`。
  static String streamFailed(String raw, {bool isRemote = false}) {
    final reason = briefReason(raw);
    if (isRemote || looksNetwork(raw)) {
      return reason.isEmpty
          ? '播放中断，请检查网络后重试'
          : '播放中断，请检查网络后重试（$reason）';
    }
    return reason.isEmpty ? '播放出错，请重试' : '播放出错：$reason';
  }

  /// 供 UI / 测试复用：是否像网络类失败。
  static bool looksNetwork(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return false;
    return RegExp(
      r'timeout|timed?\s*out|SocketException|Failed host lookup|'
      r'Connection refused|Network is unreachable|Connection reset|'
      r'ClientException|HttpException|handshake|SSL|TLS|'
      r'unreachable|offline|ENOTFOUND|ECONNREFUSED|ECONNRESET|'
      r'network|dns|resolve',
      caseSensitive: false,
    ).hasMatch(s);
  }

  /// 截断、脱敏、映射常见英文为短中文原因；纯英文噪声可返回空。
  static String briefReason(Object error) {
    var s = sanitizeErrorText(
      error is String ? error : error.toString(),
      '',
    );
    if (s.isEmpty) return '';
    s = s.replaceFirst(
      RegExp(r'^(Exception|Error|MediaKitException):\s*', caseSensitive: false),
      '',
    );
    s = s.trim();
    if (s.isEmpty) return '';

    if (RegExp(r'timeout|timed?\s*out', caseSensitive: false).hasMatch(s)) {
      return '超时';
    }
    if (RegExp(
      r'Failed host lookup|SocketException|Connection refused|'
      r'Network is unreachable|Connection reset|ENOTFOUND|ECONNREFUSED',
      caseSensitive: false,
    ).hasMatch(s)) {
      return '网络不可用';
    }
    if (RegExp(r'\b401\b|Unauthorized', caseSensitive: false).hasMatch(s)) {
      return '未授权';
    }
    if (RegExp(r'\b403\b|Forbidden', caseSensitive: false).hasMatch(s)) {
      return '无权限或链接失效';
    }
    if (RegExp(r'\b404\b|Not Found', caseSensitive: false).hasMatch(s)) {
      return '资源不存在';
    }
    if (RegExp(r'codec|unsupported|demux|decode', caseSensitive: false)
        .hasMatch(s)) {
      return '格式不支持或无法解码';
    }
    if (looksNetwork(s) && _mostlyLatin(s)) {
      return '';
    }
    if (s.length > 72) {
      s = '${s.substring(0, 72)}…';
    }
    return s;
  }

  static bool _mostlyLatin(String s) {
    final letters = RegExp(r'[A-Za-z]').allMatches(s).length;
    final cjk = RegExp(r'[\u4e00-\u9fff]').allMatches(s).length;
    return letters >= 12 && cjk == 0;
  }
}
