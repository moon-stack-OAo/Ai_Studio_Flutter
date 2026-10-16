import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('长行、换行、CRLF、代理对：任意增量边界都能无损拼回全文', () {
    for (final text in [
      List.filled(15000, '字').join(),
      List.filled(6000, '行\r\n').join(),
      '${List.filled(4095, 'x').join()}😀${List.filled(5000, 'y').join()}',
      '${List.filled(4095, 'x').join()}\r\n${List.filled(5000, 'y').join()}',
      '${List.filled(4095, 'x').join()}👨‍👩‍👧‍👦${List.filled(5000, 'y').join()}',
      '${List.filled(4095, 'x').join()}e\u0301${List.filled(5000, 'y').join()}',
    ]) {
      final chunks = StreamingTextChunks();
      List<String> previous = [];
      for (var end = 1; end < text.length; end += 37) {
        final prefix = text.substring(0, end);
        chunks.update(prefix);
        expect([...chunks.stable, chunks.tail].join(), prefix);
        expect(chunks.stable.take(previous.length), previous);
        for (final block in chunks.stable) {
          expect(
            block.length,
            lessThanOrEqualTo(StreamingTextChunks.blockSize),
          );
          final last = block.codeUnitAt(block.length - 1);
          expect(last >= 0xd800 && last <= 0xdbff, isFalse);
          expect(last, isNot(0x0d));
        }
        previous = chunks.stable;
      }
      chunks.update(text);
      expect([...chunks.stable, chunks.tail].join(), text);
    }
  });

  test('替换、截短和清空会重置稳定前缀', () {
    final chunks = StreamingTextChunks();
    chunks.update(List.filled(10000, 'a').join());
    chunks.update('新文本');
    expect(chunks.stable, isEmpty);
    expect(chunks.tail, '新文本');
    chunks.update('');
    expect(chunks.tail, isEmpty);
  });
}
