import 'package:flutter/material.dart';

/// 长文案默认折叠为 [maxLines] 行，超出可展开/收起。
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

  @override
  Widget build(BuildContext context) {
    final linkColor =
        widget.linkColor ?? Theme.of(context).colorScheme.primary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final exceeds = _exceeds(constraints.maxWidth);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              style: widget.style,
              maxLines: _expanded ? null : widget.maxLines,
              overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            ),
            if (exceeds)
              TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: linkColor,
                ),
                child: Text(_expanded ? '收起' : '展开'),
              ),
          ],
        );
      },
    );
  }
}
