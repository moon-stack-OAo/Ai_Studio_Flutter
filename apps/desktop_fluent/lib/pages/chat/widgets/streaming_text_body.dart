import 'package:core/core.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/rendering.dart'
    show ClearSelectionEvent, SelectedContent;

/// Fluent 自己的选择区域和文本控件；仅与另一端共享字符串分段。
class StreamingTextBody extends StatefulWidget {
  const StreamingTextBody({super.key, required this.data, required this.style});

  final String data;
  final TextStyle style;

  @override
  State<StreamingTextBody> createState() => _StreamingTextBodyState();
}

class _StreamingTextBodyState extends State<StreamingTextBody> {
  final _chunks = StreamingTextChunks();
  final List<Widget> _prefix = [];
  final _selection = _StreamingSelectionDelegate();
  TextStyle? _style;
  String _previous = '';

  @override
  void didUpdateWidget(StreamingTextBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.data.startsWith(oldWidget.data)) {
      _selection.dispatchSelectionEvent(const ClearSelectionEvent());
    }
  }

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.style != _style || !widget.data.startsWith(_previous)) {
      _prefix.clear();
    }
    _style = widget.style;
    _previous = widget.data;
    _chunks.update(widget.data);
    final stable = _chunks.stable;
    if (stable.isEmpty) {
      return SelectableText(widget.data, style: widget.style);
    }
    for (var i = _prefix.length; i < stable.length; i++) {
      // Column 已承接自然换行，去掉末尾换行避免额外空行；复制按选区映射回原文。
      _prefix.add(
        RepaintBoundary(
          child: Text(_displayBlock(stable[i]), style: widget.style),
        ),
      );
    }
    _selection
      ..text = widget.data
      ..stable = stable;
    return SelectionArea(
      child: SelectionContainer(
        delegate: _selection,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ..._prefix,
            Text(_chunks.tail, style: widget.style),
          ],
        ),
      ),
    );
  }
}

String _displayBlock(String block) => block.endsWith('\r\n')
    ? block.substring(0, block.length - 2)
    : block.endsWith('\n')
    ? block.substring(0, block.length - 1)
    : block;

/// 显示块省略的换行只在选区跨过边界时恢复；部分选择不会扩大成全文。
class _StreamingSelectionDelegate extends StaticSelectionContainerDelegate {
  String text = '';
  List<String> stable = const [];

  int _sourceOffset(int offset, {required bool start}) {
    var boundary = 0;
    var source = offset;
    for (final block in stable) {
      final removed = block.endsWith('\r\n')
          ? 2
          : (block.endsWith('\n') ? 1 : 0);
      boundary += block.length - removed;
      if (offset > boundary || (start && offset == boundary)) source += removed;
    }
    return source;
  }

  @override
  SelectedContent? getSelectedContent() {
    final range = getSelection();
    if (range == null || range.startOffset == range.endOffset) return null;
    final forward = range.startOffset < range.endOffset;
    return SelectedContent(
      plainText: text.substring(
        _sourceOffset(
          forward ? range.startOffset : range.endOffset,
          start: true,
        ),
        _sourceOffset(
          forward ? range.endOffset : range.startOffset,
          start: false,
        ),
      ),
    );
  }
}
