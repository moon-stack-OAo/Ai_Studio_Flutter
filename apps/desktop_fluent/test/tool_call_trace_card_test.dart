import 'package:core/core.dart';
import 'package:desktop_fluent/pages/chat/widgets/tool_call_trace_card.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const trace = ChatToolCallTrace(
  toolCallId: 'call',
  serverId: 'server',
  serverDisplayName: 'Business server',
  toolName: 'search',
  status: McpToolCallStatus.success,
  argumentsSummary: 'argument-marker',
  resultSummary: 'result-marker',
);

Future<void> pump(
  WidgetTester tester,
  List<ChatToolCallTrace> traces,
  ToolTraceExpansion expansion, {
  double width = 500,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    FluentApp(
      theme: buildFluentLightTheme(),
      home: ScaffoldPage(
        content: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: SingleChildScrollView(
                child: ToolCallTraceGroup(traces: traces, expansion: expansion),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'single and multiple failures and authorization are visible while closed',
    (tester) async {
      final state = ToolTraceExpansion();
      final failed = trace.copyWith(
        status: McpToolCallStatus.failed,
        errorMessage: 'failure-marker',
      );
      await pump(tester, [failed], state);
      expect(find.text('失败 1'), findsOneWidget);
      expect(find.text('failure-marker'), findsOneWidget);
      expect(find.textContaining('参数摘要（脱敏'), findsNothing);
      await pump(tester, [
        failed,
        const ChatToolCallTrace(
          toolCallId: 'auth',
          serverId: 'server',
          serverDisplayName: 'Server',
          toolName: 'write',
          status: McpToolCallStatus.pendingAuth,
        ),
      ], state);
      expect(find.textContaining('待授权 1'), findsOneWidget);
      expect(find.text('failure-marker'), findsOneWidget);
      expect(state.expanded, isFalse);
      expect(find.byType(ToolCallTraceCard), findsNothing);
      await pump(tester, [
        failed,
        const ChatToolCallTrace(
          toolCallId: 'failed-2',
          serverId: 'server',
          serverDisplayName: '',
          toolName: 'second',
          status: McpToolCallStatus.failed,
        ),
        const ChatToolCallTrace(
          toolCallId: 'rejected',
          serverId: 'server',
          serverDisplayName: '',
          toolName: 'third',
          status: McpToolCallStatus.rejected,
        ),
        const ChatToolCallTrace(
          toolCallId: 'cancelled',
          serverId: 'server',
          serverDisplayName: '',
          toolName: 'fourth',
          status: McpToolCallStatus.cancelled,
        ),
      ], state);
      expect(find.textContaining('失败 2'), findsOneWidget);
      expect(find.textContaining('已拒绝 1'), findsOneWidget);
      expect(find.textContaining('已取消 1'), findsOneWidget);
      expect(find.byType(ToolCallTraceCard), findsNothing);
    },
  );

  testWidgets(
    'independent disclosures survive group closure and status updates',
    (tester) async {
      final state = ToolTraceExpansion();
      await pump(tester, [trace], state);
      await tester.tap(find.byKey(const ValueKey('tool-group-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('参数摘要（脱敏'));
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.text('复制参数摘要'), findsOneWidget);
      expect(find.text('复制结果摘要'), findsNothing);
      await tester.tap(find.textContaining('结果摘要（脱敏'));
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsNWidgets(2));
      await tester.tap(find.textContaining('参数摘要（脱敏'));
      await tester.pumpAndSettle();
      expect(find.text('复制参数摘要'), findsNothing);
      expect(find.text('复制结果摘要'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tool-group-toggle')));
      await tester.pumpAndSettle();
      await pump(tester, [
        trace.copyWith(status: McpToolCallStatus.pendingAuth),
      ], state);
      expect(find.textContaining('待授权 1'), findsOneWidget);
      expect(find.text('复制结果摘要'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('tool-group-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('复制结果摘要'), findsOneWidget);
      expect(find.text('复制参数摘要'), findsNothing);
    },
  );

  testWidgets('copy uses sanitized summary only', (tester) async {
    final state = ToolTraceExpansion()..expanded = true;
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pump(tester, [
      trace.copyWith(argumentsSummary: 'https://example.test/?token=abcdefghi'),
    ], state);
    await tester.tap(find.textContaining('参数摘要（脱敏'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制参数摘要'));
    await tester.pumpAndSettle();
    expect(copied, 'https://example.test/?token=***');
  });

  testWidgets(
    'missing historical result is unknown, long names cannot hide status at large scale',
    (tester) async {
      final state = ToolTraceExpansion();
      await pump(
        tester,
        [
          ChatToolCallTrace(
            toolCallId: 'call',
            serverId: 'server',
            toolName: List.filled(30, 'very-long-name').join(),
            serverDisplayName: List.filled(30, 'long-server').join(),
            status: McpToolCallStatus.pendingAuth,
          ),
        ],
        state,
        width: 220,
        scale: 2,
      );
      expect(find.text('待授权 1').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('tool-group-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('待授权').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('tool-group-toggle')));
      await tester.pumpAndSettle();
      await pump(
        tester,
        [
          trace.copyWith(
            status: McpToolCallStatus.queued,
            resultSummary: '历史记录缺少工具结果',
          ),
        ],
        state,
        width: 220,
        scale: 2,
      );
      expect(find.text('结果缺失 / 状态未知 1'), findsOneWidget);
      expect(find.text('排队中'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
