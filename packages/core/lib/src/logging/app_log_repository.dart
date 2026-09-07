import 'package:flutter/foundation.dart';

import 'app_log_entry.dart';
import 'app_log_level.dart';
import 'app_log_storage.dart';

/// 本机运行日志仓库（SET-LOGS）。
class AppLogRepository extends ChangeNotifier {
  AppLogRepository({required AppLogStorage storage}) : _storage = storage;

  static const maxEntries = 500;

  final AppLogStorage _storage;

  /// 内存顺序：最新在前。
  List<AppLogEntry> _entries = const [];
  bool _loaded = false;
  bool _loading = false;
  String? _lastError;

  bool get isLoaded => _loaded;
  bool get isLoading => _loading;
  String? get lastError => _lastError;

  /// 全部条目（最新在前）。
  List<AppLogEntry> get entries => List.unmodifiable(_entries);

  int get totalCount => _entries.length;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _lastError = null;
    notifyListeners();
    try {
      final loaded = await _storage.load();
      _entries = _normalizeNewestFirst(loaded);
      _loaded = true;
    } catch (e) {
      _lastError = e.toString();
      _entries = const [];
      _loaded = true;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<AppLogEntry> append({
    required AppLogLevel level,
    required String source,
    required String message,
    int? at,
  }) async {
    final cleaned = sanitizeLogMessage(message);
    final entry = AppLogEntry.create(
      level: level,
      source: source,
      message: cleaned,
      at: at,
    );
    final next = <AppLogEntry>[entry, ..._entries];
    _entries = _normalizeNewestFirst(next);
    notifyListeners();
    try {
      await _storage.save(_entries);
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
    }
    return entry;
  }

  /// 过滤；返回最新在前。
  ///
  /// [exactLevel] 优先于 [minLevel]；二者皆空则不过滤级别。
  List<AppLogEntry> query({
    AppLogLevel? minLevel,
    AppLogLevel? exactLevel,
    String? source,
    String? search,
  }) {
    final src = source?.trim();
    final q = search?.trim().toLowerCase();
    return [
      for (final e in _entries)
        if (_match(
          e,
          exactLevel: exactLevel,
          minLevel: minLevel,
          source: src,
          search: q,
        ))
          e,
    ];
  }

  Future<void> clear() async {
    _entries = const [];
    notifyListeners();
    try {
      await _storage.save(_entries);
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// 多行文本供复制；时间 `YYYY-MM-DD HH:mm:ss`。
  String formatVisible(List<AppLogEntry> list) {
    if (list.isEmpty) return '';
    final buf = StringBuffer();
    for (var i = 0; i < list.length; i++) {
      if (i > 0) buf.writeln();
      final e = list[i];
      buf.write(
        '${formatTimestamp(e.at)} · ${e.level.label} · ${e.source} · ${e.message}',
      );
    }
    return buf.toString();
  }

  static String formatTimestamp(int atMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(atMs, isUtc: false);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  /// 脱敏密钥并截断至 [AppLogEntry.maxMessageLength]。
  /// 思路对齐 [sanitizeErrorText]，但保留消息主体、放宽长度。
  static String sanitizeLogMessage(String? text) {
    var s = (text ?? '').trim();
    if (s.isEmpty) return '';
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
    if (s.length > AppLogEntry.maxMessageLength) {
      s = '${s.substring(0, AppLogEntry.maxMessageLength)}…';
    }
    return s;
  }

  static bool _match(
    AppLogEntry e, {
    AppLogLevel? exactLevel,
    AppLogLevel? minLevel,
    String? source,
    String? search,
  }) {
    if (exactLevel != null) {
      if (e.level != exactLevel) return false;
    } else if (minLevel != null) {
      if (e.level.severity < minLevel.severity) return false;
    }
    if (source != null && source.isNotEmpty && e.source != source) {
      return false;
    }
    if (search != null && search.isNotEmpty) {
      final hay =
          '${e.message} ${e.source} ${e.level.label} ${e.sourceLabel}'
              .toLowerCase();
      if (!hay.contains(search)) return false;
    }
    return true;
  }

  static List<AppLogEntry> _normalizeNewestFirst(List<AppLogEntry> raw) {
    final list = List<AppLogEntry>.from(raw);
    list.sort((a, b) => b.at.compareTo(a.at));
    if (list.length > maxEntries) {
      return list.sublist(0, maxEntries);
    }
    return list;
  }
}
