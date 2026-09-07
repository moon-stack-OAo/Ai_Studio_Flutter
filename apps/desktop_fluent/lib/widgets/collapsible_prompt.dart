import 'package:fluent_ui/fluent_ui.dart';

/// 长文案默认折叠为 [maxLines] 行，超出时在末行后显示 ▼/▲ 切换（非文字按钮）。
class CollapsiblePrompt extends StatefulWidget {
  const CollapsiblePrompt({
    super.key,
    required this.text,
    required this.style,
    this.maxLines = 4,
    this.linkColor,
  });

  final String text;
  final TextStyle style;
  final int maxLines;
  final Color? linkColor;

  @override
  State<CollapsiblePrompt> createState() => _CollapsiblePromptState();
}

class _CollapsiblePromptState extends State<CollapsiblePrompt> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant CollapsiblePrompt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _expanded = false;
    }
  }

  bool _exceeds(double maxWidth) {
    if (widget.text.isEmpty || maxWidth <= 0) return false;
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: widget.maxLines,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    return painter.didExceedMaxLines;
  }

  Widget _chevron(Color color) {
    final tip = _expanded ? '收起提示词' : '展开提示词';
    return Tooltip(
      message: tip,
      child: Semantics(
        button: true,
        label: tip,
        excludeSemantics: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 0, 2),
              child: Icon(
                _expanded ? FluentIcons.chevron_up : FluentIcons.chevron_down,
                size: 12,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final linkColor =
        widget.linkColor ?? FluentTheme.of(context).accentColor;
    return LayoutBuilder(
      builder: (context, constraints) {
        final exceeds = _exceeds(constraints.maxWidth);
        if (!exceeds) {
          return Text(widget.text, style: widget.style);
        }

        if (_expanded) {
          return Text.rich(
            TextSpan(
              style: widget.style,
              children: [
                TextSpan(text: widget.text),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: _chevron(linkColor),
                ),
              ],
            ),
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                widget.text,
                style: widget.style,
                maxLines: widget.maxLines,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _chevron(linkColor),
          ],
        );
      },
    );
  }
}
