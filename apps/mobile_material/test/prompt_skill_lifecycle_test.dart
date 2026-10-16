import 'dart:async';

import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_material/widgets/prompt_assist_sheet.dart';
import 'package:mobile_material/widgets/prompt_builder_panel.dart';

const _staleWarning = '技能已变更，建议重新润色';

class _PendingRequest {
  _PendingRequest(this.messages, this.onDelta);

  final List<Map<String, dynamic>> messages;
  final void Function(String, String)? onDelta;
  final result = Completer<ChatStreamResult>();

  void emit(String text) => onDelta?.call(text, text);
  void finish(String text) => result.complete(ChatStreamResult(content: text));
  void fail(Object error) => result.completeError(error);
}

/// 故意允许关闭 client 后继续回调，用于验证面板会拒绝迟到的旧请求。
class _ControlledChatClient extends OpenAiCompatibleChatClient {
  final requests = <_PendingRequest>[];

  @override
  Future<ChatStreamResult> streamChatWithCredentials(
    ActiveChatCredentials credentials, {
    required List<Map<String, dynamic>> messages,
    void Function(String delta, String fullText)? onDelta,
    void Function(String delta)? onContentDelta,
    double temperature = defaultChatTemperature,
    int? maxTokens,
    List<Map<String, dynamic>>? tools,
    Object? toolChoice,
    Duration? timeout,
    http.Client? client,
  }) {
    final request = _PendingRequest(messages, onDelta);
    requests.add(request);
    return request.result.future;
  }
}

class _PanelHarness {
  _PanelHarness({required this.domain, required this.structured});

  final PromptDomain domain;
  final bool structured;
  late final SkillRepository skills;
  late final ProviderRepository providers;
  final client = _ControlledChatClient();
  late final CustomSkill skill;
  int revision = 0;

  String get constraint => 'CONSTRAINT_$revision';
  Finder get panel => structured
      ? find.byType(PromptBuilderPanel).first
      : find.byType(PromptAssistSheet);
  Finder text(String text) =>
      find.descendant(of: panel, matching: find.text(text));

  Finder get firstOption {
    final label = PromptBuilderState(
      domain,
    ).dimensions.first.options.first.label;
    return find
        .descendant(of: panel, matching: find.widgetWithText(FilterChip, label))
        .first;
  }

  Future<void> mount(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    skill = CustomSkill(
      id: 'skill',
      name: '约束技能',
      prompt: constraint,
      targets: {
        domain == PromptDomain.image ? SkillTarget.image : SkillTarget.video,
      },
    );
    skills = SkillRepository(storage: MemorySkillStorage([skill]));
    await skills.load();
    providers = ProviderRepository(
      storage: MemoryProviderStorage(),
      connectionTester: StubProviderConnectionTester(),
    );
    await providers.load();
    await providers.updateProvider(
      providers.activeProviderId,
      baseUrl: 'https://example.com/v1',
      apiKey: 'test-key',
      chatModel: 'test-model',
    );
    addTearDown(() {
      client.close();
      providers.dispose();
      skills.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildMaterialLightTheme(),
        home: Scaffold(
          body: structured
              ? PromptBuilderPanel(
                  domain: domain,
                  onApply: (_) {},
                  providerRepository: providers,
                  chatClient: client,
                  skillRepository: skills,
                )
              : PromptAssistSheet(
                  domain: domain,
                  draftPrompt: '雨夜街道',
                  onApply: (_) {},
                  providerRepository: providers,
                  chatClient: client,
                  skillRepository: skills,
                ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (structured) {
      await tester.tap(firstOption);
      await tester.pump();
    }
  }

  Future<void> changeSkills(WidgetTester tester) async {
    revision++;
    await skills.saveSkill(skill.copyWith(prompt: constraint));
    await tester.pump();
  }

  Future<_PendingRequest> start(
    WidgetTester tester, {
    bool refine = false,
  }) async {
    final count = client.requests.length;
    await tester.tap(
      text(refine ? kPromptRefineInstructions.first : '✨ AI 润色'),
    );
    await tester.pump();
    expect(client.requests.length, count + 1);
    final request = client.requests.last;
    expect(request.messages.first['content'], contains(constraint));
    expect(text(_staleWarning), findsNothing);
    return request;
  }

  Future<void> complete(
    WidgetTester tester,
    _PendingRequest request,
    String result,
  ) async {
    request.finish(result);
    await tester.pumpAndSettle();
    expect(text(result), findsOneWidget);
  }
}

void main() {
  for (final domain in PromptDomain.values) {
    for (final structured in [false, true]) {
      final label = '${domain.name} ${structured ? '结构化' : '模板'}';

      testWidgets('$label 清结果后移除失效提示，后续技能变化不恢复旧提示，再润色用最新技能', (tester) async {
        final harness = _PanelHarness(domain: domain, structured: structured);
        await harness.mount(tester);

        for (var action = 0; action < 2; action++) {
          final request = await harness.start(tester);
          await harness.complete(tester, request, '已有结果_$action');
          await harness.changeSkills(tester);
          expect(harness.text(_staleWarning), findsOneWidget);

          if (structured) {
            if (action == 0) {
              await tester.tap(harness.firstOption);
            } else {
              await tester.tap(harness.text('清空'));
            }
          } else if (action == 0) {
            await tester.tap(harness.text('草稿'));
            await tester.pumpAndSettle();
            await tester.enterText(
              find.descendant(
                of: harness.panel,
                matching: find.byType(TextField),
              ),
              '修改后的草稿',
            );
          } else {
            final preset = getPromptPresets(domain).first;
            await tester.tap(harness.text(preset.label));
          }
          await tester.pumpAndSettle();
          expect(harness.text(_staleWarning), findsNothing);
          expect(harness.text('已有结果_$action'), findsNothing);
          await harness.changeSkills(tester);
          expect(harness.text(_staleWarning), findsNothing);

          if (structured) {
            await tester.tap(harness.firstOption);
            await tester.pump();
          }
          final next = await harness.start(tester);
          await harness.complete(tester, next, '重润色结果_$action');
          await harness.changeSkills(tester);
          expect(harness.text(_staleWarning), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });

      testWidgets('$label 取消润色及迭代清除失效提示，拒绝旧请求增量、成功和异常覆盖新结果', (tester) async {
        final harness = _PanelHarness(domain: domain, structured: structured);
        await harness.mount(tester);

        for (final outcome in ['success', 'abort', 'error']) {
          final refine = outcome != 'success';
          final first = await harness.start(tester);
          await harness.complete(tester, first, '取消前的结果');
          await harness.changeSkills(tester);
          expect(harness.text(_staleWarning), findsOneWidget);
          final cancelled = await harness.start(tester, refine: refine);
          // 尚无增量时，进行中的请求也会被标记为技能失效。
          await harness.changeSkills(tester);
          expect(harness.text(_staleWarning), findsOneWidget);
          cancelled.emit('待取消的部分结果');
          await tester.pump();
          await tester.tap(harness.text('取消'));
          await tester.pumpAndSettle();
          expect(harness.text(_staleWarning), findsNothing);
          expect(harness.text('待取消的部分结果'), findsNothing);
          expect(harness.text('已取消'), findsOneWidget);

          cancelled.emit('取消后的迟到增量');
          await harness.changeSkills(tester);
          expect(harness.text(_staleWarning), findsNothing);
          expect(harness.text('取消后的迟到增量'), findsNothing);
          final next = await harness.start(tester);
          next.emit('新请求的部分结果');
          cancelled.emit('旧请求覆盖尝试');
          await tester.pump();
          expect(harness.text('新请求的部分结果'), findsOneWidget);
          expect(harness.text('旧请求覆盖尝试'), findsNothing);

          if (!refine) {
            // 旧成功返回时，新请求仍在执行，不能清掉新请求或取消按钮。
            cancelled.finish('迟到的旧成功结果');
            await tester.pump();
            expect(harness.text('取消'), findsOneWidget);
            expect(harness.text('新请求的部分结果'), findsOneWidget);
            expect(harness.text('迟到的旧成功结果'), findsNothing);
          }
          await harness.complete(tester, next, '最终的新结果');
          if (refine) {
            // 新结果已完成后，旧取消异常也不能把新结果改成「已取消」。
            cancelled.fail(
              outcome == 'abort'
                  ? const ChatAbortException()
                  : const ChatApiException('迟到的旧异常'),
            );
            await tester.pumpAndSettle();
            expect(harness.text('最终的新结果'), findsOneWidget);
            expect(harness.text('已取消'), findsNothing);
            expect(harness.text('迟到的旧异常'), findsNothing);
          }
          await harness.changeSkills(tester);
          expect(harness.text(_staleWarning), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });

      testWidgets('$label 无结果的失败清除追踪，保留部分结果的失败仍跟踪技能变化', (tester) async {
        final harness = _PanelHarness(domain: domain, structured: structured);
        await harness.mount(tester);
        final emptyFailure = await harness.start(tester);
        await harness.changeSkills(tester);
        expect(harness.text(_staleWarning), findsOneWidget);
        emptyFailure.fail(const ChatApiException('请求失败'));
        await tester.pumpAndSettle();
        expect(harness.text(_staleWarning), findsNothing);
        await harness.changeSkills(tester);
        expect(harness.text(_staleWarning), findsNothing);

        final partialFailure = await harness.start(tester);
        partialFailure.emit('仍可参考的部分结果');
        await harness.changeSkills(tester);
        partialFailure.fail(const ChatApiException('流中断'));
        await tester.pumpAndSettle();
        expect(harness.text('仍可参考的部分结果'), findsOneWidget);
        expect(harness.text(_staleWarning), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
