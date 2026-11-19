import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

/// Owned by MessageList, not lazy list children. No execution state lives here.
class ToolTraceExpansion {
  bool expanded = false;
  final Map<String, ToolTraceDetailsExpansion> details = {};
}

class ToolTraceDetailsExpansion {
  bool arguments = false;
  bool result = false;
}

/// Fluent-only presentation of one contiguous group from the core projection.
class ToolCallTraceGroup extends StatefulWidget {
  const ToolCallTraceGroup({
    super.key,
    required this.traces,
    this.expansion,
    this.initiallyExpanded = false,
  });

  final List<ChatToolCallTrace> traces;
  final ToolTraceExpansion? expansion;
  final bool initiallyExpanded;

  @override
  State<ToolCallTraceGroup> createState() => _ToolCallTraceGroupState();
}

class _ToolCallTraceGroupState extends State<ToolCallTraceGroup> {
  late final _local = ToolTraceExpansion()..expanded = widget.initiallyExpanded;
  ToolTraceExpansion get expansion => widget.expansion ?? _local;

  @override
  Widget build(BuildContext context) {
    if (widget.traces.isEmpty) return const SizedBox.shrink();
    final tokens = fluentTokensOf(context);
    final counts = <String, int>{};
    for (final trace in widget.traces) {
      counts.update(
        _statusLabel(trace),
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final headline = widget.traces.length == 1
        ? '工具 · ${widget.traces.first.toolTitle ?? widget.traces.first.toolName}'
        : '工具调用 · ${widget.traces.length}';
    final statuses = counts.entries
        .map((entry) => '${entry.key} ${entry.value}')
        .join(' · ');
    final errors = widget.traces
        .where(
          (trace) =>
              trace.status == McpToolCallStatus.failed ||
              trace.status == McpToolCallStatus.rejected,
        )
        .map(
          (trace) => mcpSanitizeSummary(
            trace.errorMessage ?? trace.resultSummary,
            maxLen: 160,
          ),
        )
        .where((summary) => summary.isNotEmpty)
        .toList();
    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HoverButton(
            key: const ValueKey('tool-group-toggle'),
            onPressed: () =>
                setState(() => expansion.expanded = !expansion.expanded),
            builder: (context, states) => Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Icon(
                    expansion.expanded
                        ? FluentIcons.chevron_down
                        : FluentIcons.chevron_right,
                    size: 12,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        Text(
                          headline,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          statuses,
                          style: TextStyle(
                            fontSize: 12,
                            color: tokens.inkSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    expansion.expanded ? '收起' : '展开',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          if (!expansion.expanded && errors.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                errors.length == 1
                    ? errors.first
                    : '${errors.first} · 另有 ${errors.length - 1} 条错误摘要，展开查看',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: tokens.danger),
              ),
            ),
          if (expansion.expanded)
            for (final trace in widget.traces)
              ToolCallTraceCard(
                key: ValueKey(trace.toolCallId),
                trace: trace,
                showDetails: expansion.expanded,
                expansion: expansion.details.putIfAbsent(
                  trace.toolCallId,
                  ToolTraceDetailsExpansion.new,
                ),
              ),
        ],
      ),
    );
  }
}

bool _missingResult(ChatToolCallTrace trace) =>
    trace.status == McpToolCallStatus.queued &&
    trace.resultSummary == '历史记录缺少工具结果';

String _statusLabel(ChatToolCallTrace trace) => _missingResult(trace)
    ? '结果缺失 / 状态未知'
    : switch (trace.status) {
        McpToolCallStatus.queued => '排队中',
        McpToolCallStatus.pendingAuth => '待授权',
        McpToolCallStatus.running => '执行中',
        McpToolCallStatus.success => '成功',
        McpToolCallStatus.failed => '失败',
        McpToolCallStatus.rejected => '已拒绝',
        McpToolCallStatus.cancelled => '已取消',
      };

/// Expanded tool identity, independent status region and summary disclosures.
class ToolCallTraceCard extends StatefulWidget {
  const ToolCallTraceCard({
    super.key,
    required this.trace,
    this.showDetails = true,
    this.expansion,
  });
  final ChatToolCallTrace trace;
  final bool showDetails;
  final ToolTraceDetailsExpansion? expansion;

  @override
  State<ToolCallTraceCard> createState() => _ToolCallTraceCardState();
}

class _ToolCallTraceCardState extends State<ToolCallTraceCard> {
  final _local = ToolTraceDetailsExpansion();
  ToolTraceDetailsExpansion get expansion => widget.expansion ?? _local;

  @override
  Widget build(BuildContext context) {
    final trace = widget.trace;
    final tokens = fluentTokensOf(context);
    final danger =
        trace.status == McpToolCallStatus.failed ||
        trace.status == McpToolCallStatus.rejected;
    final color = danger
        ? tokens.danger
        : trace.status == McpToolCallStatus.pendingAuth || _missingResult(trace)
        ? tokens.warning
        : tokens.inkSecondary;
    // These are explicitly sanitized, truncated summaries, never raw payloads.
    final args = mcpSanitizeSummary(trace.argumentsSummary ?? '', maxLen: 800);
    final result = mcpSanitizeSummary(trace.resultSummary ?? '', maxLen: 800);
    final error = mcpSanitizeSummary(trace.errorMessage ?? '', maxLen: 800);
    final title = trace.toolTitle?.trim().isNotEmpty == true
        ? trace.toolTitle!.trim()
        : trace.toolName;
    final summary = error.isNotEmpty
        ? error
        : result.isNotEmpty
        ? result
        : args;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final name = Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: tokens.ink,
                ),
              );
              final status = Text(
                _statusLabel(trace),
                key: ValueKey('status:${trace.toolCallId}'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              );
              // Preserve a distinct status region; stack at narrow/large-text sizes.
              if (constraints.maxWidth <
                  360 * MediaQuery.textScalerOf(context).scale(1)) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [name, status],
                );
              }
              return Row(
                children: [
                  Expanded(child: name),
                  const SizedBox(width: 12),
                  status,
                ],
              );
            },
          ),
          Text(
            [
              trace.serverDisplayName.trim(),
              trace.toolName,
            ].where((part) => part.isNotEmpty).join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: tokens.inkMuted),
          ),
          if (summary.isNotEmpty)
            Text(
              summary,
              maxLines: danger || error.isNotEmpty ? null : 2,
              overflow: danger || error.isNotEmpty
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: danger || error.isNotEmpty
                    ? tokens.danger
                    : tokens.inkSecondary,
              ),
            ),
          if (widget.showDetails) ...[
            _SummaryDisclosure(
              label: '参数摘要',
              body: args.isEmpty ? '暂无参数摘要' : args,
              expanded: expansion.arguments,
              onToggle: () =>
                  setState(() => expansion.arguments = !expansion.arguments),
            ),
            _SummaryDisclosure(
              label: '结果摘要',
              body: result.isEmpty ? '暂无结果摘要' : result,
              expanded: expansion.result,
              onToggle: () =>
                  setState(() => expansion.result = !expansion.result),
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryDisclosure extends StatelessWidget {
  const _SummaryDisclosure({
    required this.label,
    required this.body,
    required this.expanded,
    required this.onToggle,
  });
  final String label;
  final String body;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      HoverButton(
        onPressed: onToggle,
        builder: (context, states) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            '${expanded ? '▾' : '▸'} $label（脱敏 / 可能截断）',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ),
      if (expanded) ...[
        SelectableText(body, style: const TextStyle(fontSize: 12)),
        Align(
          alignment: Alignment.centerLeft,
          child: Button(
            onPressed: () => Clipboard.setData(ClipboardData(text: body)),
            child: Text('复制$label'),
          ),
        ),
      ],
    ],
  );
}

/// 助手气泡内嵌的 tool_calls 发起摘要（默认折叠为「调用了 N 个工具」）。
class ToolCallsInvokedStrip extends StatefulWidget {
  const ToolCallsInvokedStrip({super.key, required this.toolCalls});

  final List<ChatToolCall> toolCalls;

  @override
  State<ToolCallsInvokedStrip> createState() => _ToolCallsInvokedStripState();
}

class _ToolCallsInvokedStripState extends State<ToolCallsInvokedStrip> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.toolCalls.isEmpty) return const SizedBox.shrink();
    final tokens = fluentTokensOf(context);
    final n = widget.toolCalls.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HoverButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            builder: (context, states) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _expanded
                        ? FluentIcons.chevron_down
                        : FluentIcons.chevron_right,
                    size: 10,
                    color: tokens.inkMuted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    n == 1
                        ? '调用了工具 · ${widget.toolCalls.first.name}'
                        : '调用了 $n 个工具',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: tokens.inkSecondary,
                      fontFamily: tokens.fontFamily,
                    ),
                  ),
                ],
              );
            },
          ),
          if (_expanded) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in widget.toolCalls)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.surfaceMuted,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: tokens.border),
                    ),
                    child: Text(
                      c.name,
                      style: TextStyle(
                        fontSize: 11,
                        color: tokens.inkSecondary,
                        fontFamily: tokens.fontFamily,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// role=tool 消息的轻量结果气泡（默认折叠）。
class ToolResultBubbleBody extends StatefulWidget {
  const ToolResultBubbleBody({super.key, required this.message});

  final ChatMessage message;

  @override
  State<ToolResultBubbleBody> createState() => _ToolResultBubbleBodyState();
}

class _ToolResultBubbleBodyState extends State<ToolResultBubbleBody> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    final raw = widget.message.content.trim().isEmpty
        ? '（无内容）'
        : widget.message.content;
    final summary = mcpSanitizeSummary(raw, maxLen: 120);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HoverButton(
          onPressed: () => setState(() => _expanded = !_expanded),
          builder: (context, states) {
            return Row(
              children: [
                Icon(
                  _expanded
                      ? FluentIcons.chevron_down
                      : FluentIcons.chevron_right,
                  size: 10,
                  color: tokens.inkMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _expanded ? '工具结果' : '工具结果 · $summary',
                    maxLines: _expanded ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: tokens.inkMuted,
                      fontFamily: tokens.fontFamily,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        if (_expanded) ...[
          const SizedBox(height: 6),
          SelectableText(
            mcpSanitizeSummary(raw, maxLen: 800),
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: tokens.inkSecondary,
              fontFamily: tokens.fontFamily,
            ),
          ),
        ],
      ],
    );
  }
}
