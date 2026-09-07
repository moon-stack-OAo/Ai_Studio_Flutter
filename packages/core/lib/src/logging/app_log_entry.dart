import '../util/id.dart';
import 'app_log_level.dart';

/// 建议来源 wire 与中文标签。
class AppLogSources {
  AppLogSources._();

  static const chat = 'chat';
  static const image = 'image';
  static const video = 'video';
  static const updater = 'updater';
  static const system = 'system';
  static const http = 'http';

  static const all = <String>[chat, image, video, updater, system, http];

  static String labelZh(String source) => switch (source) {
        chat => '对话',
        image => '生图',
        video => '生视频',
        updater => '更新',
        system => '系统',
        http => '网络',
        _ => source,
      };
}

/// 单条运行日志。
class AppLogEntry {
  const AppLogEntry({
    this.id,
    required this.at,
    required this.level,
    required this.source,
    required this.message,
  });

  static const maxMessageLength = 2048;

  final String? id;

  /// Unix 毫秒时间戳。
  final int at;

  final AppLogLevel level;

  /// 来源 wire：`chat` / `image` / `video` / `updater` / `system` / `http` …
  final String source;

  final String message;

  String get sourceLabel => AppLogSources.labelZh(source);

  DateTime get atDateTime =>
      DateTime.fromMillisecondsSinceEpoch(at, isUtc: false);

  AppLogEntry copyWith({
    String? id,
    int? at,
    AppLogLevel? level,
    String? source,
    String? message,
  }) {
    return AppLogEntry(
      id: id ?? this.id,
      at: at ?? this.at,
      level: level ?? this.level,
      source: source ?? this.source,
      message: message ?? this.message,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'at': at,
        'level': level.wire,
        'source': source,
        'message': message,
      };

  factory AppLogEntry.fromJson(Map<String, dynamic> json) {
    final atRaw = json['at'];
    final at = atRaw is int
        ? atRaw
        : (atRaw is num
            ? atRaw.toInt()
            : int.tryParse(atRaw?.toString() ?? '') ?? 0);
    return AppLogEntry(
      id: json['id']?.toString(),
      at: at,
      level: AppLogLevel.parse(json['level']?.toString()),
      source: (json['source']?.toString() ?? AppLogSources.system).trim(),
      message: json['message']?.toString() ?? '',
    );
  }

  factory AppLogEntry.create({
    required AppLogLevel level,
    required String source,
    required String message,
    int? at,
    String? id,
  }) {
    return AppLogEntry(
      id: id ?? createId('log'),
      at: at ?? DateTime.now().millisecondsSinceEpoch,
      level: level,
      source: source.trim().isEmpty ? AppLogSources.system : source.trim(),
      message: message,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppLogEntry &&
          id == other.id &&
          at == other.at &&
          level == other.level &&
          source == other.source &&
          message == other.message;

  @override
  int get hashCode => Object.hash(id, at, level, source, message);
}
