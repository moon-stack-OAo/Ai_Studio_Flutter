import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';

/// 一轮多个工具调用的聚合折叠（默认收起）。
class ToolCallTraceGroup extends StatefulWidget {
  const ToolCallTraceGroup({
    super.key,
    required this.traces,
    this.initiallyExpanded = false,
  });

  final List<ChatToolCallTrace> traces;
  final bool initiallyExpanded;

  @override
  State<ToolCallTraceGroup> createState() => _ToolCallTraceGroupState();
}

class _ToolCallTraceGroupState extends State<ToolCallTraceGroup> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  void didUpdateWidget(covariant ToolCallTraceGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    final needsAttention = widget.traces.any(
      (t) =>
          t.status == McpToolCallStatus.pendingAuth ||
          t.status == McpToolCallStatus.running ||
          t.status == McpToolCallStatus.queued,
    );
    if (needsAttention && !_expanded) {
      _expanded = true;
    }
  }

  String _headline() {
    final n = widget.traces.length;
    if (n == 0) return '工具调用';
    if (n == 1) {
      final t = widget.traces.first;
      final name = (t.toolTitle?.trim().isNotEmpty == true)
          ? t.toolTitle!.trim()
          : t.toolName;
      return '工具 · $name';
    }
    final ok =
        widget.traces.where((t) => t.status == McpToolCallStatus.success).length;
    final fail = widget.traces
        .where(
          (t) =>
              t.status == McpToolCallStatus.failed ||
              t.status == McpToolCallStatus.rejected ||
              t.status == McpToolCallStatus.cancelled,
        )
        .length;
    final pending = widget.traces
        .where(
          (t) =>
              t.status == McpToolCallStatus.pendingAuth ||
              t.status == McpToolCallStatus.running ||
              t.status == McpToolCallStatus.queued,
        )
        .length;
    final parts = <String>['已调用 $n 个工具'];
    if (ok > 0) parts.add('成功 $ok');
    if (fail > 0) parts.add('失败/拒绝 $fail');
    if (pending > 0) parts.add('进行中 $pending');
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    if (widget.traces.isEmpty) return const SizedBox.shrink();
    final tokens = materialTokensOf(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Color.lerp(tokens.surface, tokens.canvas, 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
              child: Row(
                children: [
                  Icon(
                    _expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 20,
                    color: tokens.inkMuted,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _headline(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: tokens.ink,
                        fontFamily: tokens.fontFamily,
                      ),
                    ),
                  ),
                  Text(
                    _expanded ? '收起' : '展开',
                    style: TextStyle(
                      fontSize: 12,
                      color: tokens.inkMuted,
                      fontFamily: tokens.fontFamily,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Column(
                children: [
                  for (final t in widget.traces) ToolCallTraceCard(trace: t),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// CHAT-TOOL-CALL：单条工具调用轨迹卡（可展开参数/结果摘要）。
class ToolCallTraceCard extends StatefulWidget {
  const ToolCallTraceCard({
    super.key,
    required this.trace,
  });

  final ChatToolCallTrace trace;

  @override
  State<ToolCallTraceCard> createState() => _ToolCallTraceCardState();
}

class _ToolCallTraceCardState extends State<ToolCallTraceCard> {
  bool _expanded = false;

  ChatToolCallTrace get trace => widget.trace;

  String get _statusLabel => switch (trace.status) {
        McpToolCallStatus.queued => '排队中',
        McpToolCallStatus.pendingAuth => '待授权',
        McpToolCallStatus.running => '执行中',
        McpToolCallStatus.success => '成功',
        McpToolCallStatus.failed => '失败',
        McpToolCallStatus.rejected => '已拒绝',
        McpToolCallStatus.cancelled => '已取消',
      };

  Color _statusColor(MaterialTokens tokens) => switch (trace.status) {
        McpToolCallStatus.success => tokens.success,
        McpToolCallStatus.failed ||
        McpToolCallStatus.rejected ||
        McpToolCallStatus.cancelled =>
          tokens.danger,
        McpToolCallStatus.pendingAuth => tokens.warning,
        McpToolCallStatus.running || McpToolCallStatus.queued => tokens.primary,
      };

  String get _title {
    final t = trace.toolTitle?.trim();
    if (t != null && t.isNotEmpty) return t;
    return trace.toolName;
  }

  String get _summaryLine {
    final err = trace.errorMessage?.trim();
    if (err != null && err.isNotEmpty) return err;
    final result = trace.resultSummary?.trim();
    if (result != null && result.isNotEmpty) return result;
    final args = trace.argumentsSummary?.trim();
    if (args != null && args.isNotEmpty) return args;
    return '';
  }

  bool get _canExpand {
    final a = trace.argumentsSummary?.trim();
    final r = trace.resultSummary?.trim();
    final e = trace.errorMessage?.trim();
    return (a != null && a.isNotEmpty) ||
        (r != null && r.isNotEmpty) ||
        (e != null && e.isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    final statusFg = _statusColor(tokens);
    final summary = _summaryLine;
    final server = trace.serverDisplayName.trim();

    return Material(
      color: Color.lerp(tokens.surface, tokens.canvas, 0.35),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _canExpand
            ? () => setState(() => _expanded = !_expanded)
            : null,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: tokens.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.build_circle_outlined, size: 16, color: statusFg),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: tokens.ink,
                        fontFamily: tokens.fontFamily,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Color.lerp(statusFg, tokens.surface, 0.88),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Color.lerp(statusFg, tokens.border, 0.55)!,
                      ),
                    ),
                    child: Text(
                      _statusLabel,
                      style: TextStyle(
                        fontSize: 10,
                        color: statusFg,
                        fontFamily: tokens.fontFamily,
                      ),
                    ),
                  ),
                  if (_canExpand) ...[
                    const SizedBox(width: 4),
                    Icon(
                      _expanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 18,
                      color: tokens.inkMuted,
                    ),
                  ],
                ],
              ),
              if (server.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  server,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: tokens.inkMuted,
                    fontFamily: tokens.fontFamily,
                  ),
                ),
              ],
              if (!_expanded && summary.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: tokens.inkSecondary,
                    fontFamily: tokens.fontFamily,
                  ),
                ),
              ],
              if (_expanded) ...[
                if (trace.argumentsSummary?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  _DetailBlock(
                    label: '参数',
                    body: trace.argumentsSummary!.trim(),
                    tokens: tokens,
                  ),
                ],
                if (trace.resultSummary?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  _DetailBlock(
                    label: '结果',
                    body: trace.resultSummary!.trim(),
                    tokens: tokens,
                  ),
                ],
                if (trace.errorMessage?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  _DetailBlock(
                    label: '错误',
                    body: trace.errorMessage!.trim(),
                    tokens: tokens,
                    danger: true,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 助手气泡内嵌的 tool_calls 发起摘要（默认折叠）。
class ToolCallsInvokedStrip extends StatefulWidget {
  const ToolCallsInvokedStrip({
    super.key,
    required this.toolCalls,
  });

  final List<ChatToolCall> toolCalls;

  @override
  State<ToolCallsInvokedStrip> createState() => _ToolCallsInvokedStripState();
}

class _ToolCallsInvokedStripState extends State<ToolCallsInvokedStrip> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.toolCalls.isEmpty) return const SizedBox.shrink();
    final tokens = materialTokensOf(context);
    final n = widget.toolCalls.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    _expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 18,
                    color: tokens.inkMuted,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
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
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in widget.toolCalls)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: tokens.surfaceMuted,
                      borderRadius: BorderRadius.circular(8),
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
  const ToolResultBubbleBody({
    super.key,
    required this.message,
  });

  final ChatMessage message;

  @override
  State<ToolResultBubbleBody> createState() => _ToolResultBubbleBodyState();
}

class _ToolResultBubbleBodyState extends State<ToolResultBubbleBody> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    final raw = widget.message.content.trim().isEmpty
        ? '（无内容）'
        : widget.message.content;
    final summary = mcpSanitizeSummary(raw, maxLen: 120);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  _expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 18,
                  color: tokens.inkMuted,
                ),
                const SizedBox(width: 4),
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
            ),
          ),
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

class _DetailBlock extends StatelessWidget {
  const _DetailBlock({
    required this.label,
    required this.body,
    required this.tokens,
    this.danger = false,
  });

  final String label;
  final String body;
  final MaterialTokens tokens;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: tokens.inkMuted,
            fontFamily: tokens.fontFamily,
          ),
        ),
        const SizedBox(height: 4),
        SelectableText(
          body,
          style: TextStyle(
            fontSize: 12,
            height: 1.4,
            color: danger ? tokens.danger : tokens.inkSecondary,
            fontFamily: tokens.fontFamily,
          ),
        ),
      ],
    );
  }
}
