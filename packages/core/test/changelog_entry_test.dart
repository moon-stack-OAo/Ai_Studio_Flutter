import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseChangelogMarkdown', () {
    test('parses Keep a Changelog headers newest-first', () {
      const src = '''
# Changelog

## [Unreleased]

### Added

- WIP

---

## [1.0.6] — 2026-09-14

### Added

- **对话附图**

### Fixed

- bug

---

## [1.0.5] — 2026-09-01

### Added

- 许可入口
''';
      final entries = parseChangelogMarkdown(src);
      expect(entries.length, 2);
      expect(entries[0].version, '1.0.6');
      expect(entries[0].date, '2026-09-14');
      expect(entries[0].bodyMarkdown.contains('对话附图'), isTrue);
      expect(entries[0].bodyMarkdown.contains('### Added'), isTrue);
      expect(entries[1].version, '1.0.5');
      expect(entries[1].date, '2026-09-01');
    });

    test('skips empty and sorts when out of order', () {
      const src = '''
## [1.0.1] — 2026-01-01

### Fixed

- a

## [1.0.2] — 2026-02-01

### Added

- b
''';
      final entries = parseChangelogMarkdown(src);
      expect(entries.map((e) => e.version).toList(), ['1.0.2', '1.0.1']);
    });
  });

  group('annotateChangelogEntries', () {
    test('marks current and latest', () {
      final annotated = annotateChangelogEntries(
        const [
          ChangelogEntry(version: '1.0.6', bodyMarkdown: 'a'),
          ChangelogEntry(version: '1.0.5', bodyMarkdown: 'b'),
        ],
        '1.0.5',
      );
      expect(annotated[0].isLatest, isTrue);
      expect(annotated[0].isCurrent, isFalse);
      expect(annotated[0].statusPill, '最新');
      expect(annotated[1].isCurrent, isTrue);
      expect(annotated[1].isLatest, isFalse);
      expect(annotated[1].statusPill, '当前');
    });

    test('installed is latest when equal', () {
      final annotated = annotateChangelogEntries(
        const [
          ChangelogEntry(version: '1.0.6', bodyMarkdown: 'a'),
        ],
        'v1.0.6+123',
      );
      expect(annotated.single.isCurrent, isTrue);
      expect(annotated.single.isLatest, isTrue);
      expect(annotated.single.statusPill, '当前');
    });
  });

  group('resolveChangelogEntries', () {
    const sample = '''
## [1.0.6] — 2026-09-14

### Added

- local six

---

## [1.0.0] — 2026-09-08

### Added

- first
''';

    test('uses bundled source and annotates', () {
      final entries = resolveChangelogEntries(
        currentVersion: '1.0.6',
        bundledSource: sample,
      );
      expect(entries, isNotEmpty);
      expect(entries.first.version, '1.0.6');
      expect(entries.first.isCurrent, isTrue);
      expect(entries.first.isLatest, isTrue);
      expect(entries.any((e) => e.version == '1.0.0'), isTrue);
    });

    test('prepends remote newer version from notes', () {
      final entries = resolveChangelogEntries(
        currentVersion: '1.0.6',
        bundledSource: '''
## [1.0.6] — 2026-09-14

### Added

- local
''',
        remoteVersion: '1.0.7',
        remoteNotes: '### Added\n\n- remote feature',
        remotePubDate: '2026-09-20T12:00:00Z',
      );
      expect(entries.first.version, '1.0.7');
      expect(entries.first.date, '2026-09-20');
      expect(entries.first.bodyMarkdown.contains('remote feature'), isTrue);
      expect(entries.first.isLatest, isTrue);
      expect(entries[1].version, '1.0.6');
      expect(entries[1].isCurrent, isTrue);
    });

    test('overrides matching version body with remote notes', () {
      final entries = resolveChangelogEntries(
        currentVersion: '1.0.5',
        bundledSource: '''
## [1.0.6] — 2026-09-14

### Added

- bundled long
''',
        remoteVersion: '1.0.6',
        remoteNotes: '### Added\n\n- release short',
      );
      expect(entries.single.version, '1.0.6');
      expect(entries.single.bodyMarkdown.contains('release short'), isTrue);
      expect(entries.single.bodyMarkdown.contains('bundled'), isFalse);
      expect(entries.single.isLatest, isTrue);
      expect(entries.single.isCurrent, isFalse);
    });
  });

  group('loadBundledChangelogMarkdown', () {
    tearDown(() {
      changelogAssetLoaderOverride = null;
      clearChangelogMarkdownCache();
    });

    test('uses asset loader override and caches', () async {
      var calls = 0;
      changelogAssetLoaderOverride = (path) async {
        calls += 1;
        expect(path, isNotEmpty);
        return '## [9.9.9] — 2099-01-01\n\n### Added\n\n- from asset\n';
      };
      clearChangelogMarkdownCache();
      final first = await loadBundledChangelogMarkdown(forceReload: true);
      final second = await loadBundledChangelogMarkdown();
      expect(first.contains('9.9.9'), isTrue);
      expect(second, first);
      expect(calls, 1);

      final entries = await resolveChangelogEntriesAsync(
        currentVersion: '9.9.9',
      );
      expect(entries.single.version, '9.9.9');
      expect(entries.single.isCurrent, isTrue);
    });

    test('falls back when all asset paths fail', () async {
      changelogAssetLoaderOverride = (_) async {
        throw StateError('missing');
      };
      clearChangelogMarkdownCache();
      final text = await loadBundledChangelogMarkdown(forceReload: true);
      expect(text, kBundledChangelogMarkdown);
    });
  });
}
