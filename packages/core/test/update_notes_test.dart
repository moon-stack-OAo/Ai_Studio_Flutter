import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prepareUpdateNotes keeps markdown and truncates', () {
    final out = prepareUpdateNotes(
      '### Changed\n\n- **Material 开屏**：去掉 logo\n\n\n- 其它',
      maxChars: 40,
    );
    expect(out.contains('###'), isTrue);
    expect(out.contains('**'), isTrue);
    expect(out.contains('开屏'), isTrue);
    expect(out.endsWith('…'), isTrue);
  });

  test('prepareUpdateNotes drops heavily corrupted text', () {
    expect(
      prepareUpdateNotes('坏\uFFFD掉\uFFFD的\uFFFD说明'),
      isEmpty,
    );
  });

  test('sanitizeUpdateNotes aliases prepareUpdateNotes', () {
    expect(
      sanitizeUpdateNotes('### A\n\n- **b**'),
      prepareUpdateNotes('### A\n\n- **b**'),
    );
  });
}
