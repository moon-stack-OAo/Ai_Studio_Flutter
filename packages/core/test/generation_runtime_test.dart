import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GenerationRuntime', () {
    test('begin/end 基本路径', () {
      final rt = GenerationRuntime();
      expect(rt.busy, isFalse);
      expect(rt.sessionId, isNull);

      final token = rt.begin('s1', () {});
      expect(rt.busy, isTrue);
      expect(rt.sessionId, 's1');
      expect(rt.isCurrent('s1'), isTrue);
      expect(rt.isCurrent('other'), isFalse);

      rt.end('s1', token);
      expect(rt.busy, isFalse);
      expect(rt.sessionId, isNull);
    });

    test('第二次 begin 会 abort 第一次', () {
      final rt = GenerationRuntime();
      var firstCancelled = 0;
      var secondCancelled = 0;

      final t1 = rt.begin('s1', () => firstCancelled++);
      expect(rt.busy, isTrue);

      final t2 = rt.begin('s2', () => secondCancelled++);
      expect(firstCancelled, 1);
      expect(secondCancelled, 0);
      expect(rt.sessionId, 's2');
      expect(rt.isCurrent('s2'), isTrue);
      expect(rt.isCurrent('s1'), isFalse);

      // 旧 finally 不得清掉新任务。
      rt.end('s1', t1);
      expect(rt.busy, isTrue);
      expect(rt.sessionId, 's2');

      rt.end('s2', t2);
      expect(rt.busy, isFalse);
    });

    test('abort 调用 cancelFn，busy 仍由 end 清理', () {
      final rt = GenerationRuntime();
      var cancelled = 0;
      final token = rt.begin('s1', () => cancelled++);

      rt.abort('s1');
      expect(cancelled, 1);
      expect(rt.busy, isTrue);

      rt.end('s1', token);
      expect(rt.busy, isFalse);
    });

    test('abort 后 busy=false（经 end）', () {
      final rt = GenerationRuntime();
      var cancelled = 0;
      late final Object token;
      token = rt.begin('chat-1', () {
        cancelled++;
        // 模拟 cancel 触发 finally → end
        rt.end('chat-1', token);
      });

      expect(rt.busy, isTrue);
      rt.abort();
      expect(cancelled, 1);
      expect(rt.busy, isFalse);
    });

    test('跨 session 覆盖：旧 end 无效，新 abort 命中', () {
      final rt = GenerationRuntime();
      var cancelled = <String>[];

      final t1 = rt.begin('chat-a', () => cancelled.add('chat-a'));
      final t2 = rt.begin('image-b', () => cancelled.add('image-b'));

      expect(cancelled, ['chat-a']);
      expect(rt.sessionId, 'image-b');

      rt.end('chat-a', t1);
      expect(rt.busy, isTrue);

      rt.abort('image-b');
      expect(cancelled, ['chat-a', 'image-b']);

      rt.end('image-b', t2);
      expect(rt.busy, isFalse);
    });

    test('abort 指定非当前 session 为 no-op', () {
      final rt = GenerationRuntime();
      var cancelled = 0;
      rt.begin('s1', () => cancelled++);
      rt.abort('other');
      expect(cancelled, 0);
      expect(rt.busy, isTrue);
    });

    test('abortIfSession 仅命中当前', () {
      final rt = GenerationRuntime();
      var cancelled = 0;
      rt.begin('s1', () => cancelled++);
      rt.abortIfSession('other');
      expect(cancelled, 0);
      rt.abortIfSession('s1');
      expect(cancelled, 1);
    });

    test('token 防旧 finally：错误 token 的 end 无效', () {
      final rt = GenerationRuntime();
      final t1 = rt.begin('s1', () {});
      final t2 = rt.begin('s1', () {});
      rt.end('s1', t1);
      expect(rt.busy, isTrue);
      rt.end('s1', t2);
      expect(rt.busy, isFalse);
    });
  });
}
