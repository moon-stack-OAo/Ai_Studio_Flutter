import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../../widgets/back_to_top_host.dart';
import '../../chat/widgets/markdown_host.dart';

/// SET-ABOUT · FB-UPDATE：多版本折叠更新日志（页内摘要 + 完整 ContentDialog）。
class ChangelogSection extends StatelessWidget {
  const ChangelogSection({
    super.key,
    required this.entries,
    required this.currentVersionLabel,
    this.summaryMaxItems = 4,
  });

  final List<ChangelogEntry> entries;
  final String currentVersionLabel;

  /// 页内摘要最多展示条数；完整层展示全部。
  final int summaryMaxItems;

  List<ChangelogEntry> get _summaryEntries {
    if (entries.length <= summaryMaxItems) return entries;
    return entries.take(summaryMaxItems).toList(growable: false);
  }

  Future<void> openFullHistory(BuildContext context) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return _ChangelogHistoryDialog(
          entries: entries,
          currentVersionLabel: currentVersionLabel,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    if (entries.isEmpty) {
      return Text(
        '暂无更新日志',
        style: TextStyle(
          fontSize: 12,
          color: tokens.inkMuted,
          fontFamily: tokens.fontFamily,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 页内跟关于页 ListView 同滚，避免嵌套滚动条。
        ChangelogEntryList(
          entries: _summaryEntries,
          scrollable: false,
        ),
        const SizedBox(height: 4),
        HyperlinkButton(
          onPressed: () => openFullHistory(context),
          child: const Text('查看完整更新日志…'),
        ),
      ],
    );
  }
}

class _ChangelogHistoryDialog extends StatefulWidget {
  const _ChangelogHistoryDialog({
    required this.entries,
    required this.currentVersionLabel,
  });

  final List<ChangelogEntry> entries;
  final String currentVersionLabel;

  @override
  State<_ChangelogHistoryDialog> createState() =>
      _ChangelogHistoryDialogState();
}

class _ChangelogHistoryDialogState extends State<_ChangelogHistoryDialog> {
  final ScrollController _scroll = ScrollController();
  bool _showBackToTop = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final show = _scroll.hasClients && _scroll.offset > 80;
    if (show != _showBackToTop) {
      setState(() => _showBackToTop = show);
    }
  }

  Future<void> _scrollToTop() async {
    if (!_scroll.hasClients) return;
    await _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
      title: const Text('更新日志'),
      content: SizedBox(
        width: 700,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '完整历史 · Keep a Changelog · 已安装 ${widget.currentVersionLabel}',
              style: TextStyle(
                fontSize: 12,
                color: tokens.inkMuted,
                fontFamily: tokens.fontFamily,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: tokens.canvas,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: tokens.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: ChangelogEntryList(
                          entries: widget.entries,
                          scrollable: true,
                          controller: _scroll,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 20,
                      bottom: 20,
                      child: IgnorePointer(
                        ignoring: !_showBackToTop,
                        child: AnimatedOpacity(
                          opacity: _showBackToTop ? 1 : 0,
                          duration: const Duration(milliseconds: 160),
                          child: BackToTopButton(onPressed: _scrollToTop),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        Button(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class ChangelogEntryList extends StatefulWidget {
  const ChangelogEntryList({
    super.key,
    required this.entries,
    this.scrollable = false,
    this.controller,
  });

  final List<ChangelogEntry> entries;
  final bool scrollable;
  final ScrollController? controller;

  @override
  State<ChangelogEntryList> createState() => _ChangelogEntryListState();
}

class _ChangelogEntryListState extends State<ChangelogEntryList> {
  /// 默认全部折叠；同一列表内可多开。
  final Set<String> _expanded = <String>{};

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      for (var i = 0; i < widget.entries.length; i++) ...[
        if (i > 0) const SizedBox(height: 8),
        _ChangelogRow(
          entry: widget.entries[i],
          expanded: _expanded.contains(widget.entries[i].version),
          onToggle: () {
            setState(() {
              final v = widget.entries[i].version;
              if (_expanded.contains(v)) {
                _expanded.remove(v);
              } else {
                _expanded.add(v);
              }
            });
          },
        ),
      ],
    ];

    if (!widget.scrollable) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }

    return SingleChildScrollView(
      controller: widget.controller,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _ChangelogRow extends StatefulWidget {
  const _ChangelogRow({
    required this.entry,
    required this.expanded,
    required this.onToggle,
  });

  final ChangelogEntry entry;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  State<_ChangelogRow> createState() => _ChangelogRowState();
}

class _ChangelogRowState extends State<_ChangelogRow> {
  bool _detailsOpen = false;

  @override
  void didUpdateWidget(covariant _ChangelogRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.expanded && oldWidget.expanded) {
      _detailsOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    final entry = widget.entry;
    final expanded = widget.expanded;
    final pill = entry.statusPill;
    final summary = prepareUpdateNotes(
      entry.summaryMarkdown ?? '',
      maxChars: 12000,
    );
    final body = prepareUpdateNotes(entry.bodyMarkdown, maxChars: 12000);
    final showSummaryFirst = entry.hasSummary;
    final empty = !entry.hasSummary && body.isEmpty;

    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HoverButton(
            onPressed: widget.onToggle,
            builder: (ctx, states) {
              final hovered = states.isHovered || states.isPressed;
              return Container(
                constraints: const BoxConstraints(minHeight: 40),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                color: hovered
                    ? Color.lerp(tokens.primary, tokens.surfaceMuted, 0.92)
                    : null,
                child: Row(
                  children: [
                    AnimatedRotation(
                      turns: expanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: Text(
                        '›',
                        style: TextStyle(
                          fontSize: 14,
                          color: tokens.inkMuted,
                          fontFamily: tokens.fontFamily,
                          height: 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      entry.versionLabel,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: tokens.ink,
                        fontFamily: tokens.monoFontFamily,
                        fontFamilyFallback: kFluentMonoFontFamilyFallback,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        entry.dateLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: tokens.inkMuted,
                          fontFamily: tokens.fontFamily,
                        ),
                      ),
                    ),
                    if (pill != null) ...[
                      const SizedBox(width: 8),
                      _StatusPill(
                        label: pill,
                        warn: pill == '最新' && !entry.isCurrent,
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          if (expanded) ...[
            Container(height: 1, color: tokens.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(36, 10, 12, 12),
              child: empty
                  ? Text(
                      '暂无说明',
                      style: TextStyle(
                        fontSize: 12,
                        color: tokens.inkMuted,
                        fontFamily: tokens.fontFamily,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showSummaryFirst)
                          MarkdownHost(data: summary, compact: true)
                        else
                          MarkdownHost(data: body, compact: true),
                        if (showSummaryFirst && body.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          HyperlinkButton(
                            onPressed: () {
                              setState(() => _detailsOpen = !_detailsOpen);
                            },
                            child: Text(
                              _detailsOpen ? '收起详细变更' : '显示详细变更',
                            ),
                          ),
                          if (_detailsOpen) ...[
                            const SizedBox(height: 4),
                            Text(
                              '详细变更',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: tokens.inkMuted,
                                fontFamily: tokens.fontFamily,
                              ),
                            ),
                            const SizedBox(height: 6),
                            MarkdownHost(data: body, compact: true),
                          ],
                        ],
                      ],
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, this.warn = false});

  final String label;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    final fg = warn ? tokens.primaryPressed : tokens.success;
    final bg = warn
        ? Color.lerp(tokens.primary, tokens.surface, 0.88)!
        : Color.lerp(tokens.success, tokens.surface, 0.88)!;
    final border = warn
        ? Color.lerp(tokens.primary, tokens.border, 0.55)!
        : Color.lerp(tokens.success, tokens.border, 0.55)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: fg,
          fontFamily: tokens.fontFamily,
        ),
      ),
    );
  }
}
