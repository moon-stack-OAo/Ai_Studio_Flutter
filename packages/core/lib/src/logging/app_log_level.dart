/// 运行日志级别（SET-LOGS）。
enum AppLogLevel {
  debug,
  info,
  warn,
  error;

  String get wire => name;

  /// UI / 复制用大写标签。
  String get label => switch (this) {
        AppLogLevel.debug => 'DEBUG',
        AppLogLevel.info => 'INFO',
        AppLogLevel.warn => 'WARN',
        AppLogLevel.error => 'ERROR',
      };

  /// 中文短标签。
  String get labelZh => switch (this) {
        AppLogLevel.debug => '调试',
        AppLogLevel.info => '信息',
        AppLogLevel.warn => '警告',
        AppLogLevel.error => '错误',
      };

  int get severity => switch (this) {
        AppLogLevel.debug => 0,
        AppLogLevel.info => 1,
        AppLogLevel.warn => 2,
        AppLogLevel.error => 3,
      };

  static AppLogLevel? tryParse(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'debug':
        return AppLogLevel.debug;
      case 'info':
        return AppLogLevel.info;
      case 'warn':
      case 'warning':
        return AppLogLevel.warn;
      case 'error':
        return AppLogLevel.error;
      default:
        return null;
    }
  }

  static AppLogLevel parse(String? raw, [AppLogLevel fallback = AppLogLevel.info]) {
    return tryParse(raw) ?? fallback;
  }
}
