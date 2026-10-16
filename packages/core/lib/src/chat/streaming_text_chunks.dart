// 当前直接依赖没有纯 Dart 的字素入口；仅取 Flutter 公共导出的 Characters，
// 不引入 Widget 符号，也不直接依赖未在 pubspec 声明的传递依赖 characters。
import 'package:flutter/widgets.dart' show Characters;

/// 流式纯文本的稳定前缀。优先在换行处分块，无换行时限制单块长度。
/// 只冻结仍有后续内容的块，保留 CRLF、代理对和组合字符的字素边界。
class StreamingTextChunks {
  static const int blockSize = 4096;
  final List<String> _stable = [];
  String _text = '';
  int _offset = 0;
  String tail = '';

  List<String> get stable => List.unmodifiable(_stable);

  void update(String text) {
    if (text == _text) return;
    if (!text.startsWith(_text)) {
      _stable.clear();
      _offset = 0;
    }
    _text = text;
    while (text.length - _offset > blockSize) {
      var end = _offset + blockSize;
      final newline = text.lastIndexOf('\n', end - 1);
      if (newline >= _offset + blockSize ~/ 2) {
        end = newline + 1;
      } else {
        var boundary = _offset;
        for (final character in Characters(text.substring(_offset))) {
          if (boundary + character.length > end) break;
          boundary += character.length;
        }
        // 单个超长字素不能安全拆开，留在可变尾块。
        if (boundary == _offset) break;
        end = boundary;
      }
      _stable.add(text.substring(_offset, end));
      _offset = end;
    }
    tail = text.substring(_offset);
  }
}
