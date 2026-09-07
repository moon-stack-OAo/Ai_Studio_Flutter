import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('createId prefixes and is unique enough', () {
    final a = createId('provider');
    final b = createId('provider');
    expect(a.startsWith('provider_'), isTrue);
    expect(a, isNot(equals(b)));
  });

  test('builtin presets expose three model fields', () {
    final presets = builtinProviderPresets();
    expect(presets, isNotEmpty);
    for (final p in presets) {
      expect(p.builtin, isTrue);
      expect(p.chatModel, isNotEmpty);
      expect(p.toJsonMeta().containsKey('apiKey'), isFalse);
    }
  });
}
