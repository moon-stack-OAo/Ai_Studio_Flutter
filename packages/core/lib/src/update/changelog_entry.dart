import 'package:flutter/services.dart' show rootBundle;

import 'update_notes.dart';
import 'version_compare.dart';

/// 多版本更新日志单行（Keep a Changelog 段落）。
///
/// 运行时优先读 [kChangelogAssetPath]（由 `sync-changelog-asset.mjs` 从仓库根
/// `CHANGELOG.md` 同步）；失败时回退 [kBundledChangelogMarkdown] 最小兜底。
/// 与 OD `SET-ABOUT` 折叠行对齐。浏览历史 ≠ 有更新态。
class ChangelogEntry {
  const ChangelogEntry({
    required this.version,
    this.date,
    required this.bodyMarkdown,
    this.isCurrent = false,
    this.isLatest = false,
  });

  /// 规范化前的版本号（如 `1.0.6`），展示时加方括号。
  final String version;

  /// ISO 日期 `yyyy-MM-dd`；解析不到时为 null。
  final String? date;

  /// 该版本正文（含 `### Added` 等），供 [prepareUpdateNotes] + Markdown 渲染。
  final String bodyMarkdown;

  /// 与当前安装版本相等。
  final bool isCurrent;

  /// 列表中最新一版（目录头）；可与 [isCurrent] 同时为 true（已装即最新）。
  final bool isLatest;

  String get versionLabel => '[${normalizeVersion(version)}]';

  String get dateLabel =>
      (date != null && date!.trim().isNotEmpty) ? date!.trim() : '—';

  /// 行上状态 pill：优先「当前」，否则「最新」。
  String? get statusPill {
    if (isCurrent) return '当前';
    if (isLatest) return '最新';
    return null;
  }

  ChangelogEntry copyWith({
    String? version,
    String? date,
    String? bodyMarkdown,
    bool? isCurrent,
    bool? isLatest,
  }) {
    return ChangelogEntry(
      version: version ?? this.version,
      date: date ?? this.date,
      bodyMarkdown: bodyMarkdown ?? this.bodyMarkdown,
      isCurrent: isCurrent ?? this.isCurrent,
      isLatest: isLatest ?? this.isLatest,
    );
  }
}

/// core 包内 CHANGELOG asset（`rootBundle` 须带 `packages/core/` 前缀）。
const String kChangelogAssetPath = 'packages/core/assets/CHANGELOG.md';

/// [loadBundledChangelogMarkdown] 依次尝试的路径。
const List<String> kChangelogAssetCandidates = [
  kChangelogAssetPath,
  'assets/CHANGELOG.md',
];

String? _cachedChangelogMarkdown;

/// 测试可注入；生产为 null 时走 [rootBundle]。
typedef ChangelogAssetLoader = Future<String> Function(String assetPath);

ChangelogAssetLoader? changelogAssetLoaderOverride;

/// 清除内存缓存（测试或热重载后强制重读）。
void clearChangelogMarkdownCache() {
  _cachedChangelogMarkdown = null;
}

/// 异步加载打包的 CHANGELOG 全文；失败则返回 [kBundledChangelogMarkdown]。
Future<String> loadBundledChangelogMarkdown({
  bool forceReload = false,
}) async {
  if (!forceReload) {
    final cached = _cachedChangelogMarkdown;
    if (cached != null && cached.isNotEmpty) return cached;
  }

  final loader = changelogAssetLoaderOverride ?? _defaultAssetLoader;
  final tried = <String>{};
  for (final path in kChangelogAssetCandidates) {
    if (!tried.add(path)) continue;
    try {
      final text = (await loader(path)).replaceAll('\r\n', '\n').trim();
      if (text.isEmpty) continue;
      _cachedChangelogMarkdown = text;
      return text;
    } catch (_) {
      // 尝试下一候选路径
    }
  }

  _cachedChangelogMarkdown = kBundledChangelogMarkdown;
  return kBundledChangelogMarkdown;
}

Future<String> _defaultAssetLoader(String assetPath) {
  return rootBundle.loadString(assetPath);
}

final _headerRe = RegExp(
  r'^##\s+\[([^\]]+)\](?:\s*[—–\-]\s*(\d{4}-\d{2}-\d{2}))?\s*$',
  multiLine: true,
);

/// 解析 Keep a Changelog 风格 Markdown 为版本条目（新→旧）。
///
/// 跳过 `[Unreleased]`；忽略章节之间的 `---`。
List<ChangelogEntry> parseChangelogMarkdown(String source) {
  final text = source.replaceAll('\r\n', '\n').trim();
  if (text.isEmpty) return const [];

  final matches = _headerRe.allMatches(text).toList();
  if (matches.isEmpty) return const [];

  final out = <ChangelogEntry>[];
  for (var i = 0; i < matches.length; i++) {
    final m = matches[i];
    final verRaw = (m.group(1) ?? '').trim();
    if (verRaw.isEmpty) continue;
    if (verRaw.toLowerCase() == 'unreleased') continue;

    final start = m.end;
    final end = i + 1 < matches.length ? matches[i + 1].start : text.length;
    var body = text.substring(start, end).trim();
    body = body.replaceAll(RegExp(r'^---\s*', multiLine: true), '').trim();
    body = body.replaceAll(RegExp(r'\n---\s*$'), '').trim();
    body = body.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();

    out.add(
      ChangelogEntry(
        version: normalizeVersion(verRaw),
        date: m.group(2),
        bodyMarkdown: body,
      ),
    );
  }

  out.sort((a, b) => compareVersions(b.version, a.version));
  return out;
}

/// 标注「当前 / 最新」pill；[entries] 应为新→旧。
List<ChangelogEntry> annotateChangelogEntries(
  List<ChangelogEntry> entries,
  String? currentVersion,
) {
  if (entries.isEmpty) return const [];
  final current = normalizeVersion(currentVersion);
  final latestVer = entries.first.version;
  return [
    for (final e in entries)
      e.copyWith(
        isCurrent: current.isNotEmpty && compareVersions(e.version, current) == 0,
        isLatest: compareVersions(e.version, latestVer) == 0,
      ),
  ];
}

/// 合并本地 changelog 与可选的远端单次检查 notes。
///
/// - 无远端多版本 API 时，以 [bundledSource] 为主（通常来自 asset）。
/// - 若检查到比嵌入头更新的 [remoteVersion]，则在列表头插入一条（body=notes）。
/// - 若远端版本已在列表中且 notes 非空，用远端 notes 覆盖该条正文。
List<ChangelogEntry> resolveChangelogEntries({
  required String? currentVersion,
  String? bundledSource,
  String? remoteVersion,
  String? remoteNotes,
  String? remotePubDate,
}) {
  final source = (bundledSource != null && bundledSource.trim().isNotEmpty)
      ? bundledSource
      : (_cachedChangelogMarkdown ?? kBundledChangelogMarkdown);
  final parsed = parseChangelogMarkdown(source);
  final remoteVer = normalizeVersion(remoteVersion);
  final notes = prepareUpdateNotes(remoteNotes ?? '', maxChars: 12000);

  if (remoteVer.isNotEmpty && notes.isNotEmpty) {
    final idx = parsed.indexWhere(
      (e) => compareVersions(e.version, remoteVer) == 0,
    );
    final date = _tryIsoDate(remotePubDate);
    if (idx < 0) {
      parsed.insert(
        0,
        ChangelogEntry(
          version: remoteVer,
          date: date,
          bodyMarkdown: notes,
        ),
      );
      parsed.sort((a, b) => compareVersions(b.version, a.version));
    } else {
      parsed[idx] = parsed[idx].copyWith(
        bodyMarkdown: notes,
        date: date ?? parsed[idx].date,
      );
    }
  }

  return annotateChangelogEntries(parsed, currentVersion);
}

/// 先 [loadBundledChangelogMarkdown]，再 [resolveChangelogEntries]。
Future<List<ChangelogEntry>> resolveChangelogEntriesAsync({
  required String? currentVersion,
  String? remoteVersion,
  String? remoteNotes,
  String? remotePubDate,
  bool forceReload = false,
}) async {
  final bundled = await loadBundledChangelogMarkdown(forceReload: forceReload);
  return resolveChangelogEntries(
    currentVersion: currentVersion,
    bundledSource: bundled,
    remoteVersion: remoteVersion,
    remoteNotes: remoteNotes,
    remotePubDate: remotePubDate,
  );
}

String? _tryIsoDate(String? raw) {
  if (raw == null) return null;
  final m = RegExp(r'(\d{4}-\d{2}-\d{2})').firstMatch(raw.trim());
  return m?.group(1);
}

/// Asset 不可用时的最小兜底（勿再手工维护全文；以根 `CHANGELOG.md` 为准）。
const String kBundledChangelogMarkdown = r'''
## [1.0.6] — 2026-09-14

### Added

- 首个可交付与后续版本说明见应用内更新日志（CHANGELOG asset）

---

## [1.0.0] — 2026-09-08

### Added

- 首个正式可交付：双端对话 / 生图 / 生视频 / 设置与直链更新
''';
