import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Presentation choices owned by MessageList, outside disposable lazy children.
class ToolTraceExpansion {
  bool expanded = false;
  final Map<String, ToolTraceDetailsExpansion> details = {};
}

class ToolTraceDetailsExpansion {
  bool arguments = false;
  bool result = false;
}

/// Material-only presentation of a contiguous group from the core projection.
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
    final tokens = materialTokensOf(context);
    final counts = <String, int>{};
    for (final trace in widget.traces) {
      counts.update(_statusLabel(trace), (n) => n + 1, ifAbsent: () => 1);
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: tokens.surfaceMuted,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: tokens.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              button: true,
              expanded: expansion.expanded,
              child: InkWell(
                key: const ValueKey('tool-group-toggle'),
                onTap: () =>
                    setState(() => expansion.expanded = !expansion.expanded),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          expansion.expanded
                              ? Icons.expand_more
                              : Icons.chevron_right,
                          size: 20,
                          color: tokens.inkMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                headline,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: tokens.ink,
                                ),
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
                      ],
                    ),
                  ),
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
                  expansion: expansion.details.putIfAbsent(
                    trace.toolCallId,
                    ToolTraceDetailsExpansion.new,
                  ),
                ),
          ],
        ),
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

class ToolCallTraceCard extends StatefulWidget {
  const ToolCallTraceCard({super.key, required this.trace, this.expansion});
  final ChatToolCallTrace trace;
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
    final tokens = materialTokensOf(context);
    final danger =
        trace.status == McpToolCallStatus.failed ||
        trace.status == McpToolCallStatus.rejected;
    final color = danger
        ? tokens.danger
        : trace.status == McpToolCallStatus.pendingAuth || _missingResult(trace)
        ? tokens.warning
        : tokens.inkSecondary;
    // The UI only displays/copies sanitized, potentially truncated summaries.
    final args = mcpSanitizeSummary(trace.argumentsSummary ?? '', maxLen: 800);
    final result = mcpSanitizeSummary(trace.resultSummary ?? '', maxLen: 800);
    final error = mcpSanitizeSummary(trace.errorMessage ?? '', maxLen: 800);
    final summary = error.isNotEmpty
        ? error
        : result.isNotEmpty
        ? result
        : args;
    final title = trace.toolTitle?.trim().isNotEmpty == true
        ? trace.toolTitle!.trim()
        : trace.toolName;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
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
      Semantics(
        button: true,
        expanded: expanded,
        child: InkWell(
          onTap: onToggle,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '${expanded ? '▾' : '▸'} $label（脱敏 / 可能截断）',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
        ),
      ),
      if (expanded) ...[
        SelectableText(body, style: const TextStyle(fontSize: 12)),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => Clipboard.setData(ClipboardData(text: body)),
            child: Text('复制$label'),
          ),
        ),
      ],
    ],
  );
}

/// Legacy inline invocation strip; projected groups normally replace it.
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: () => setState(() => _expanded = !_expanded),
          child: Text(
            widget.toolCalls.length == 1
                ? '调用了工具 · ${widget.toolCalls.first.name}'
                : '调用了 ${widget.toolCalls.length} 个工具',
          ),
        ),
        if (_expanded)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final call in widget.toolCalls) Chip(label: Text(call.name)),
            ],
          ),
      ],
    );
  }
}

/// Legacy fallback for unprojected tool messages.
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
    final raw = widget.message.content.trim().isEmpty
        ? '（无内容）'
        : widget.message.content;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: () => setState(() => _expanded = !_expanded),
          child: Text(
            _expanded
                ? '工具结果'
                : '工具结果 · ${mcpSanitizeSummary(raw, maxLen: 120)}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (_expanded) SelectableText(mcpSanitizeSummary(raw, maxLen: 800)),
      ],
    );
  }
}
