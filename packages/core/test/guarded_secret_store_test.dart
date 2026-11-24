import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

class _DelayedSecrets extends MemorySecretStore {
  final pending = Completer<void>();
  @override
  Future<void> write(String key, String value) async {
    await pending.future;
    await super.write(key, value);
  }
}

void main() {
  testWidgets('timeout leaves barrier until actual completion; no raw error', (tester) async {
    final backing = _DelayedSecrets();
    final store = GuardedSecretStore(backing);
    final operation = store.write('key', 'SENSITIVE_SENTINEL');
    final assertion = expectLater(operation, throwsA(predicate((e) => !e.toString().contains('SENSITIVE_SENTINEL'))));
    await tester.pump(const Duration(seconds: 9));
    await assertion;
    expect(store.isPending, isTrue);
    await expectLater(store.read('key'), throwsStateError);
    await expectLater(store.delete('key'), throwsStateError);
    await expectLater(store.write('key', 'new'), throwsStateError);
    expect(identical(GuardedSecretStore(backing), store), isTrue);
    backing.pending.complete();
    await tester.pump();
    expect(store.isPending, isFalse);
    expect(await store.read('key'), 'SENSITIVE_SENTINEL');
  });
}
