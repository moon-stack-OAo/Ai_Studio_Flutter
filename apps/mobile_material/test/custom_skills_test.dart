import 'dart:async';

import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_material/pages/chat/widgets/message_bubble.dart';
import 'package:mobile_material/pages/settings/settings_skills_tab.dart';
import 'package:mobile_material/widgets/prompt_assist_sheet.dart';
import 'package:mobile_material/widgets/prompt_builder_panel.dart';
import 'package:mobile_material/widgets/skill_summary.dart';

const _imageSkill = CustomSkill(
  id: 'image-skill',
  name: '图像技能',
  prompt: 'IMAGE_CONSTRAINT',
  rules: 'IMAGE_RULE',
  targets: {SkillTarget.image},
);

Future<SkillRepository> _repository([
  List<CustomSkill> skills = const [],
]) async {
  final repository = SkillRepository(storage: MemorySkillStorage(skills));
  await repository.load();
  return repository;
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildMaterialLightTheme(),
      home: Scaffold(body: child),
    ),
  );
  await tester.pumpAndSettle();
}

class _FailingStorage extends MemorySkillStorage {
  _FailingStorage() : super([_imageSkill]);
  @override
  Future<void> save(List<CustomSkill> skills) async =>
      throw StateError('测试存储失败');
}

class _PendingStorage extends MemorySkillStorage {
  _PendingStorage(super.initial);

  final pending = Completer<void>();
  int saveCalls = 0;

  @override
  Future<void> save(List<CustomSkill> skills) async {
    saveCalls++;
    await pending.future;
    await super.save(skills);
  }
}

Finder _skillRow(String id) => find.byKey(ValueKey(id));

Finder _skillHandle(String id) => find.descendant(
  of: _skillRow(id),
  matching: find.byType(ReorderableDragStartListener),
);

Future<void> _menuAction(WidgetTester tester, String id, String action) async {
  await tester.tap(
    find.descendant(of: _skillRow(id), matching: find.byTooltip('技能操作')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(action));
  await tester.pumpAndSettle();
}

Future<void> _dragSkill(
  WidgetTester tester,
  String source,
  String target, {
  bool settle = true,
}) async {
  final start = tester.getCenter(_skillHandle(source));
  final targetRect = tester.getRect(_skillRow(target));
  final end = Offset(start.dx, targetRect.center.dy);
  final gesture = await tester.startGesture(start);
  // 模拟连续触控移动，让列表在拖动过程中更新占位与目标位置。
  for (var step = 1; step <= 12; step++) {
    await gesture.moveTo(Offset.lerp(start, end, step / 12)!);
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump(const Duration(milliseconds: 300));
  await gesture.up();
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // 等待放下动画完成，保存仍由测试控制。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
  }
}

class _RecordingChatClient extends OpenAiCompatibleChatClient {
  final requests = <List<Map<String, dynamic>>>[];
  final firstResult = Completer<ChatStreamResult>();

  @override
  Future<ChatStreamResult> streamChatWithCredentials(
    ActiveChatCredentials credentials, {
    required List<Map<String, dynamic>> messages,
    void Function(String delta, String fullText)? onDelta,
    double temperature = defaultChatTemperature,
    int? maxTokens,
    List<Map<String, dynamic>>? tools,
    Object? toolChoice,
    Duration? timeout,
    http.Client? client,
  }) {
    requests.add(messages);
    onDelta?.call('保留润色结果', '保留润色结果');
    return requests.length == 1
        ? firstResult.future
        : Future.value(const ChatStreamResult(content: '下一版润色结果'));
  }
}

void main() {
  testWidgets('全屏编辑显式保存；系统返回可继续编辑、保存或放弃', (tester) async {
    final repo = await _repository();
    addTearDown(repo.dispose);
    await _pump(tester, SettingsSkillsTab(repository: repo));
    await tester.tap(find.text('新建技能'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '我的技能');
    await tester.enterText(find.byType(TextField).at(1), '描述文本');
    await tester.enterText(find.byType(TextField).at(2), '技能提示词');
    await tester.tap(find.widgetWithText(FilterChip, '生图'));
    await tester.tap(find.widgetWithText(FilterChip, '对话'));
    await tester.ensureVisible(find.byType(TextField).at(3));
    await tester.enterText(find.byType(TextField).at(3), '技能规则');
    expect(repo.skills, isEmpty);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('保存技能修改？'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(find.byType(SkillEditorPage), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(repo.skills.single.name, '我的技能');
    expect(repo.skills.single.description, '描述文本');
    expect(repo.skills.single.prompt, '技能提示词');
    expect(repo.skills.single.rules, '技能规则');
    expect(repo.skills.single.targets, {SkillTarget.image, SkillTarget.chat});
    await _menuAction(tester, repo.skills.single.id, '编辑');
    await tester.enterText(find.byType(TextField).at(0), '未保存名称');
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃'));
    await tester.pumpAndSettle();
    expect(repo.skills.single.name, '我的技能');
  });

  testWidgets('列表支持复制默认停用、排序、类型筛选、启用和确认删除', (tester) async {
    final repo = await _repository([
      _imageSkill,
      _imageSkill.copyWith(
        id: 'video',
        name: '视频技能',
        targets: {SkillTarget.video},
      ),
    ]);
    addTearDown(repo.dispose);
    await _pump(tester, SettingsSkillsTab(repository: repo));
    expect(find.byTooltip('上移'), findsNothing);
    expect(find.byTooltip('下移'), findsNothing);
    expect(find.byType(IconButton), findsNWidgets(2));
    await _menuAction(tester, _imageSkill.id, '复制（默认停用）');
    expect(repo.skills.last.name, '图像技能 副本');
    expect(repo.skills.last.enabled, isFalse);
    expect(repo.skills.last.id, isNot(_imageSkill.id));
    expect(find.byType(SkillEditorPage), findsNothing);
    await _dragSkill(tester, 'video', _imageSkill.id);
    expect(repo.skills.first.name, '视频技能');
    await tester.tap(find.widgetWithText(ChoiceChip, '生视频'));
    await tester.pumpAndSettle();
    expect(find.text('视频技能'), findsOneWidget);
    expect(find.text('图像技能'), findsNothing);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(repo.activeFor(SkillTarget.video), isEmpty);
    await _menuAction(tester, 'video', '删除');
    expect(repo.skills.length, 3);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(repo.skills.length, 2);
  });

  testWidgets('存储失败保留编辑内容并显示错误', (tester) async {
    final repo = SkillRepository(storage: _FailingStorage());
    await repo.load();
    addTearDown(repo.dispose);
    await _pump(tester, SettingsSkillsTab(repository: repo));
    await _menuAction(tester, _imageSkill.id, '编辑');
    expect(find.byType(SwitchListTile), findsNothing);
    await tester.enterText(find.byType(TextField).at(0), '新名称');
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.textContaining('测试存储失败'),
      ),
      findsOneWidget,
    );
    expect(find.byType(SkillEditorPage), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '新名称',
    );
    expect(repo.skills.single.name, '图像技能');
  });

  testWidgets('手柄在全量和过滤列表中双向拖动，隐藏技能相对顺序保持', (tester) async {
    final storage = MemorySkillStorage([
      _imageSkill,
      _imageSkill.copyWith(
        id: 'video-1',
        name: '视频一',
        targets: {SkillTarget.video},
      ),
      _imageSkill.copyWith(id: 'image-2', name: '图像二'),
      _imageSkill.copyWith(
        id: 'video-2',
        name: '视频二',
        targets: {SkillTarget.video},
      ),
      _imageSkill.copyWith(id: 'image-3', name: '图像三'),
    ]);
    final repo = SkillRepository(storage: storage);
    await repo.load();
    addTearDown(repo.dispose);
    await _pump(tester, SettingsSkillsTab(repository: repo));

    await _dragSkill(tester, _imageSkill.id, 'image-2');
    expect(repo.skills.map((s) => s.id), [
      'video-1',
      'image-2',
      _imageSkill.id,
      'video-2',
      'image-3',
    ]);
    await _dragSkill(tester, _imageSkill.id, 'video-1');
    expect(repo.skills.map((s) => s.id), [
      _imageSkill.id,
      'video-1',
      'image-2',
      'video-2',
      'image-3',
    ]);

    await tester.tap(find.widgetWithText(ChoiceChip, '生图'));
    await tester.pumpAndSettle();
    expect(find.text('视频一'), findsNothing);
    expect(find.text('视频二'), findsNothing);
    await _dragSkill(tester, _imageSkill.id, 'image-3');
    expect(repo.skills.map((s) => s.id), [
      'video-1',
      'image-2',
      'video-2',
      'image-3',
      _imageSkill.id,
    ]);
    expect(
      tester.getTopLeft(_skillRow('image-2')).dy,
      lessThan(tester.getTopLeft(_skillRow('image-3')).dy),
    );
    expect(
      tester.getTopLeft(_skillRow('image-3')).dy,
      lessThan(tester.getTopLeft(_skillRow(_imageSkill.id)).dy),
    );
    await _dragSkill(tester, _imageSkill.id, 'image-2');
    expect(repo.skills.map((s) => s.id), [
      'video-1',
      _imageSkill.id,
      'image-2',
      'video-2',
      'image-3',
    ]);
    expect(storage.current.map((s) => s.id), repo.skills.map((s) => s.id));
    expect(tester.takeException(), isNull);
  });

  for (final filtered in [false, true]) {
    testWidgets('${filtered ? '过滤' : '全量'}列表拖动保存失败保留顺序，忙态阻止重复修改', (
      tester,
    ) async {
      final storage = _PendingStorage([
        _imageSkill,
        _imageSkill.copyWith(
          id: 'video',
          name: '视频技能',
          targets: {SkillTarget.video},
        ),
        _imageSkill.copyWith(id: 'image-2', name: '图像二'),
      ]);
      final repo = SkillRepository(storage: storage);
      await repo.load();
      addTearDown(repo.dispose);
      final original = repo.skills.map((s) => s.id).toList();
      await _pump(tester, SettingsSkillsTab(repository: repo));
      if (filtered) {
        await tester.tap(find.widgetWithText(ChoiceChip, '生图'));
        await tester.pumpAndSettle();
      }
      await _dragSkill(tester, _imageSkill.id, 'image-2', settle: false);
      expect(storage.saveCalls, 1);
      expect(repo.skills.map((s) => s.id), original);
      expect(storage.current.map((s) => s.id), original);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      for (final handle in tester.widgetList<ReorderableDragStartListener>(
        find.byType(ReorderableDragStartListener),
      )) {
        expect(handle.enabled, isFalse);
      }
      for (final toggle in tester.widgetList<Switch>(find.byType(Switch))) {
        expect(toggle.onChanged, isNull);
      }
      await tester.tap(find.byTooltip('技能操作').first);
      await tester.pump();
      expect(find.text('复制（默认停用）'), findsNothing);
      await _dragSkill(tester, 'image-2', _imageSkill.id, settle: false);
      expect(storage.saveCalls, 1);
      storage.pending.completeError(StateError('测试排序存储失败'));
      await tester.pumpAndSettle();
      expect(repo.skills.map((s) => s.id), original);
      expect(storage.current.map((s) => s.id), original);
      expect(find.textContaining('测试排序存储失败'), findsWidgets);
      expect(
        tester.getTopLeft(_skillRow(_imageSkill.id)).dy,
        lessThan(tester.getTopLeft(_skillRow('image-2')).dy),
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('手柄支持键盘和读屏排序，内容区点击仍进入全屏编辑', (tester) async {
    final repo = await _repository([
      _imageSkill,
      _imageSkill.copyWith(id: 'image-2', name: '图像二'),
    ]);
    addTearDown(repo.dispose);
    await _pump(tester, SettingsSkillsTab(repository: repo));
    Focus.of(tester.element(_skillHandle(_imageSkill.id))).requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(repo.skills.last.id, _imageSkill.id);

    final reorderSemantics = tester.widget<Semantics>(
      find
          .ancestor(
            of: _skillRow(_imageSkill.id),
            matching: find.byWidgetPredicate(
              (w) =>
                  w is Semantics &&
                  (w.properties.customSemanticsActions?.isNotEmpty ?? false),
            ),
          )
          .first,
    );
    final upLabel = WidgetsLocalizations.of(
      tester.element(_skillRow(_imageSkill.id)),
    ).reorderItemUp;
    reorderSemantics.properties.customSemanticsActions!.entries
        .singleWhere((entry) => entry.key.label == upLabel)
        .value();
    await tester.pumpAndSettle();
    expect(repo.skills.first.id, _imageSkill.id);
    await tester.tap(find.text(_imageSkill.name));
    await tester.pumpAndSettle();
    expect(find.byType(SkillEditorPage), findsOneWidget);
    expect(
      ModalRoute.of(tester.element(find.byType(SkillEditorPage))),
      isA<MaterialPageRoute<void>>().having(
        (route) => route.fullscreenDialog,
        'fullscreenDialog',
        isTrue,
      ),
    );
    expect(find.byType(SwitchListTile), findsNothing);
  });

  testWidgets('窄屏长名称与描述截断，触控目标不少于48且无溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final skill = _imageSkill.copyWith(
      name: '用于检查窄屏布局的超长技能名称LongSkillNameWithoutSpaces0123456789',
      description: '这是需要限制行数的非常长的技能描述。' * 10,
      targets: SkillTarget.values.toSet(),
    );
    final repo = await _repository([skill]);
    addTearDown(repo.dispose);
    await _pump(tester, SettingsSkillsTab(repository: repo));
    expect(tester.takeException(), isNull);
    for (final text in [skill.name, skill.description]) {
      final widget = tester.widget<Text>(find.text(text));
      expect(widget.maxLines, 2);
      expect(widget.overflow, TextOverflow.ellipsis);
    }
    for (final target in [
      _skillHandle(skill.id),
      find.byType(Switch),
      find.byTooltip('技能操作'),
    ]) {
      final size = tester.getSize(target);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
    await _menuAction(tester, skill.id, '编辑');
    expect(find.byType(SkillEditorPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('技能摘要实时刷新，最终提示词使用 core 组合，无技能仍可管理', (tester) async {
    final repo = await _repository();
    addTearDown(repo.dispose);
    await _pump(
      tester,
      SkillSummary(repository: repo, target: SkillTarget.image, prompt: '原始需求'),
    );
    expect(find.text('自定义技能 · 未启用 · 管理'), findsOneWidget);
    await repo.saveSkill(_imageSkill);
    await tester.pumpAndSettle();
    expect(find.text('生效技能：图像技能'), findsOneWidget);
    await tester.tap(find.text('最终提示词预览'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        composeSkillPrompt(
          prompt: '原始需求',
          skills: repo.snapshotFor(SkillTarget.image),
        ),
      ),
      findsOneWidget,
    );
    await repo.setEnabled(_imageSkill.id, false);
    await tester.pumpAndSettle();
    expect(find.text('自定义技能 · 未启用 · 管理'), findsOneWidget);
    expect(find.text('原始需求'), findsOneWidget);
    await tester.tap(find.text('自定义技能 · 未启用 · 管理'));
    await tester.pumpAndSettle();
    expect(find.text('没有生效的自定义技能'), findsOneWidget);
    await repo.setEnabled(_imageSkill.id, true);
    await tester.pumpAndSettle();
    expect(find.text('IMAGE_RULE'), findsOneWidget);
    await tester.tap(find.text('管理技能'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsSkillsTab), findsOneWidget);
  });

  testWidgets('历史快照独立显示保存内容，旧消息隐藏入口', (tester) async {
    const snapshot = SkillSnapshot(
      id: 'saved',
      name: '保存时名称',
      prompt: '保存时提示词',
      rules: '保存时规则',
    );
    await _pump(
      tester,
      const MessageBubble(
        message: ChatMessage(
          id: 'old',
          createdAt: 0,
          role: ChatRole.user,
          content: '旧消息',
        ),
      ),
    );
    expect(find.text('查看当次技能与提示词'), findsNothing);
    await _pump(
      tester,
      const MessageBubble(
        message: ChatMessage(
          id: 'saved',
          createdAt: 1,
          role: ChatRole.user,
          content: '新消息',
          appliedSkills: [snapshot],
        ),
      ),
    );
    await tester.tap(find.text('查看当次技能与提示词'));
    await tester.pumpAndSettle();
    expect(find.text('保存时名称'), findsOneWidget);
    expect(find.text('保存时规则'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(
      tester,
      const AppliedSkillsButton(skills: [snapshot], finalPrompt: '保存的最终提示词'),
    );
    await tester.tap(find.text('查看当次技能与提示词'));
    await tester.pumpAndSettle();
    expect(find.text('保存的最终提示词'), findsOneWidget);
  });

  for (final domain in PromptDomain.values) {
    for (final structured in [false, true]) {
      testWidgets(
        '${domain.name} ${structured ? '结构化' : '模板'}润色及三种迭代使用最新技能，生成中变化保留结果并提示',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(700, 1100));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final target = domain == PromptDomain.image
              ? SkillTarget.image
              : SkillTarget.video;
          final skill = _imageSkill.copyWith(targets: {target});
          final repo = await _repository([
            skill,
            skill.copyWith(
              id: 'chat-only',
              name: '对话专用',
              prompt: 'CHAT_ONLY',
              targets: {SkillTarget.chat},
            ),
            skill.copyWith(
              id: 'other',
              name: '另一类型',
              prompt: 'OTHER_DOMAIN',
              targets: {
                target == SkillTarget.image
                    ? SkillTarget.video
                    : SkillTarget.image,
              },
            ),
          ]);
          addTearDown(repo.dispose);
          final providers = ProviderRepository(
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
          addTearDown(providers.dispose);
          final client = _RecordingChatClient();
          addTearDown(client.close);
          await _pump(
            tester,
            structured
                ? PromptBuilderPanel(
                    domain: domain,
                    onApply: (_) {},
                    providerRepository: providers,
                    chatClient: client,
                    skillRepository: repo,
                  )
                : PromptAssistSheet(
                    domain: domain,
                    draftPrompt: '雨夜街道',
                    onApply: (_) {},
                    providerRepository: providers,
                    chatClient: client,
                    skillRepository: repo,
                  ),
          );
          if (structured) {
            final option = PromptBuilderState(
              domain,
            ).dimensions.first.options.first;
            await tester.tap(
              find.widgetWithText(FilterChip, option.label).first,
            );
            await tester.pump();
          }
          await tester.tap(find.text('✨ AI 润色').first);
          await tester.pump();
          expect(client.requests.length, 1);
          final system = client.requests.first.first['content'] as String;
          expect(system, contains('IMAGE_CONSTRAINT'));
          expect(system, isNot(contains('CHAT_ONLY')));
          expect(system, isNot(contains('OTHER_DOMAIN')));
          await repo.saveSkill(skill.copyWith(prompt: 'UPDATED_CONSTRAINT'));
          await tester.pump();
          expect(find.text('技能已变更，建议重新润色'), findsOneWidget);
          expect(find.text('保留润色结果'), findsOneWidget);
          client.firstResult.complete(
            const ChatStreamResult(content: '保留润色结果'),
          );
          await tester.pumpAndSettle();
          expect(find.text('技能已变更，建议重新润色'), findsOneWidget);
          expect(find.text('保留润色结果'), findsOneWidget);
          for (final instruction in kPromptRefineInstructions) {
            await tester.tap(
              find.widgetWithText(FilterChip, instruction).first,
            );
            await tester.pumpAndSettle();
            expect(
              client.requests.last.first['content'],
              contains('UPDATED_CONSTRAINT'),
            );
            expect(client.requests.last.last['content'], contains(instruction));
            expect(find.text('技能已变更，建议重新润色'), findsNothing);
          }
          await repo.setEnabled(skill.id, false);
          await tester.pumpAndSettle();
          expect(find.text('下一版润色结果'), findsOneWidget);
          expect(find.text('技能已变更，建议重新润色'), findsOneWidget);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
