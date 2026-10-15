import 'dart:async';

import 'package:core/core.dart';
import 'package:desktop_fluent/app/theme_controller.dart';
import 'package:desktop_fluent/main.dart';
import 'package:desktop_fluent/pages/chat/widgets/message_bubble.dart';
import 'package:desktop_fluent/pages/image/widgets/image_timeline.dart';
import 'package:desktop_fluent/pages/settings/settings_skills_page.dart';
import 'package:desktop_fluent/pages/video/widgets/video_queue.dart';
import 'package:desktop_fluent/widgets/prompt_assist_panel.dart';
import 'package:desktop_fluent/widgets/prompt_builder_panel.dart';
import 'package:desktop_fluent/widgets/skill_summary.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

const _skill = CustomSkill(
  id: 's1',
  name: '画面保真',
  prompt: '保持原主体',
  rules: '避免增加角色',
  targets: {SkillTarget.image, SkillTarget.video},
);

const _sortSkills = [
  _skill,
  CustomSkill(
    id: 'hidden1',
    name: '隐藏对话一',
    prompt: '对话规则一',
    targets: {SkillTarget.chat},
  ),
  CustomSkill(
    id: 's2',
    name: '图片技能二',
    prompt: '图片规则二',
    targets: {SkillTarget.image},
  ),
  CustomSkill(
    id: 'hidden2',
    name: '隐藏对话二',
    prompt: '对话规则二',
    targets: {SkillTarget.chat},
  ),
  CustomSkill(
    id: 's3',
    name: '图片技能三',
    prompt: '图片规则三',
    targets: {SkillTarget.image},
  ),
];

Finder _dragHandle(String id) => find.byKey(ValueKey('skill_drag_$id'));

Future<void> _skillMenu(WidgetTester tester, String id, String action) async {
  await tester.tap(find.byKey(ValueKey('skill_actions_$id')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: find.byType(MenuFlyout), matching: find.text(action)),
  );
  await tester.pumpAndSettle();
}

Future<void> _dragSkill(
  WidgetTester tester,
  String source,
  String destination,
) async {
  final start = tester.getCenter(_dragHandle(source));
  final target = tester.getCenter(_dragHandle(destination));
  final gesture = await tester.startGesture(
    start,
    kind: PointerDeviceKind.mouse,
  );
  // 连续鼠标移动穿过条目中点，让占位动画随手势更新。
  final steps = ((target.dy - start.dy).abs() / 8).ceil();
  for (var step = 1; step <= steps; step++) {
    await gesture.moveTo(Offset.lerp(start, target, step / steps)!);
    await tester.pump(const Duration(milliseconds: 30));
  }
  await tester.pump(const Duration(milliseconds: 300));
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> _semanticMove(WidgetTester tester, String id, String label) async {
  final node = tester.getSemantics(_dragHandle(id));
  final actionId = node
      .getSemanticsData()
      .customSemanticsActionIds!
      .singleWhere((id) => CustomSemanticsAction.getAction(id)!.label == label);
  node.owner!.performAction(node.id, SemanticsAction.customAction, actionId);
  await tester.pumpAndSettle();
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    FluentApp(
      theme: buildFluentLightTheme(),
      home: ScaffoldPage(content: child),
    ),
  );
  await tester.pumpAndSettle();
}

Future<SkillRepository> _repository([SkillStorage? storage]) async {
  final repo = SkillRepository(
    storage: storage ?? MemorySkillStorage([_skill]),
  );
  await repo.load();
  return repo;
}

class _FailingStorage extends MemorySkillStorage {
  _FailingStorage([super.initial = const [_skill]]);
  @override
  Future<void> save(List<CustomSkill> skills) async =>
      throw StateError('磁盘不可写');
}

class _PendingStorage extends MemorySkillStorage {
  _PendingStorage() : super(_sortSkills);

  final pending = Completer<void>();
  int writes = 0;

  @override
  Future<void> save(List<CustomSkill> skills) async {
    writes++;
    await pending.future;
    await super.save(skills);
  }
}

class _EnhanceClient extends OpenAiCompatibleChatClient {
  final requests = <List<Map<String, dynamic>>>[];
  final pending = <Completer<ChatStreamResult>>[];

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
    onDelta?.call('流式结果', '流式结果');
    final completer = Completer<ChatStreamResult>();
    pending.add(completer);
    return completer.future;
  }
}

void main() {
  testWidgets('技能设置分类、主导航和返回均保护未保存编辑，共用注入仓库', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final skills = await _repository();
    final providers = ProviderRepository(
      storage: MemoryProviderStorage(),
      connectionTester: StubProviderConnectionTester(),
    );
    final chats = ChatSessionRepository(storage: MemoryChatSessionStorage());
    final images = ImageSessionRepository(storage: MemoryImageSessionStorage());
    final videos = VideoSessionRepository(storage: MemoryVideoSessionStorage());
    final defaults = ChatDefaultsRepository(
      storage: MemoryChatDefaultsStorage(),
    );
    final logs = AppLogRepository(storage: MemoryAppLogStorage());
    final appearance = AppearanceRepository(storage: MemoryAppearanceStorage());
    await Future.wait([
      providers.load(),
      chats.load(),
      images.load(),
      videos.load(),
      defaults.load(),
      logs.load(),
      appearance.load(),
    ]);
    await tester.pumpWidget(
      AiStudioApp(
        skillRepository: skills,
        themeController: ThemeController(),
        providerRepository: providers,
        sessionRepository: chats,
        imageSessionRepository: images,
        videoSessionRepository: videos,
        chatDefaultsRepository: defaults,
        appLogRepository: logs,
        dataBackupService: DataBackupService(
          providers: providers,
          appearance: appearance,
          chatDefaults: defaults,
          chatSessions: chats,
          imageSessions: images,
          videoSessions: videos,
          skillRepository: skills,
        ),
        generation: GenerationRuntime(),
        showBrandIntro: false,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义技能').first);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SettingsSkillsPage>(find.byType(SettingsSkillsPage))
          .repository,
      same(skills),
    );
    await tester.tap(find.textContaining('画面保真').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('skill_name')), '导航修改');
    await tester.tap(find.text('对话默认'));
    await tester.pumpAndSettle();
    expect(find.text('技能有未保存的修改'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('对话'));
    await tester.pumpAndSettle();
    expect(find.text('技能有未保存的修改'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('技能有未保存的修改'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('对话默认'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(skills.skills.single.name, '导航修改');
    expect(find.byKey(const ValueKey('skill_name')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    skills.dispose();
  });

  testWidgets('编辑显式保存，复制默认停用，删除需确认', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = await _repository();
    addTearDown(repo.dispose);
    await _pump(tester, SettingsSkillsPage(repository: repo));
    await tester.tap(find.textContaining('画面保真').first);
    await tester.pumpAndSettle();
    expect(find.byType(ToggleSwitch), findsOneWidget);
    expect(find.text('启用技能'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('skill_name')), '保留主体');
    expect(repo.skills.single.name, '画面保真');
    await tester.ensureVisible(find.text('保存技能'));
    await tester.tap(find.text('保存技能'));
    await tester.pumpAndSettle();
    expect(repo.skills.single.name, '保留主体');
    await tester.enterText(find.byKey(const ValueKey('skill_name')), '最新主体');
    expect(find.text('复制'), findsNothing);
    expect(find.text('删除'), findsNothing);
    expect(find.text('上移'), findsNothing);
    expect(find.text('下移'), findsNothing);
    expect(find.byTooltip('技能操作'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Tooltip && widget.message == '拖动排序',
      ),
      findsOneWidget,
    );
    await _skillMenu(tester, 's1', '复制');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存技能'));
    await tester.tap(find.text('保存技能'));
    await tester.pumpAndSettle();
    expect(repo.skills.length, 2);
    expect(repo.skills.last.enabled, false);
    expect(repo.skills.first.name, '最新主体');
    expect(repo.skills.last.name, '最新主体 副本');
    final copyId = repo.skills.last.id;
    await _skillMenu(tester, copyId, '删除');
    expect(repo.skills.length, 2);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(repo.skills.length, 2);
    await _skillMenu(tester, copyId, '删除');
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(repo.skills.length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('技能启停、鼠标拖动、读屏及键盘排序和类型筛选使用仓库状态', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = await _repository();
    addTearDown(repo.dispose);
    await repo.saveSkill(
      const CustomSkill(
        id: 's2',
        name: '视频技能',
        prompt: '视频规则',
        targets: {SkillTarget.video},
      ),
    );
    await repo.saveSkill(
      const CustomSkill(
        id: 's3',
        name: '对话技能',
        prompt: '对话规则',
        targets: {SkillTarget.chat},
      ),
    );
    await _pump(tester, SettingsSkillsPage(repository: repo));
    final semantics = tester.ensureSemantics();
    expect(
      tester
          .getSemantics(_dragHandle('s1'))
          .getSemanticsData()
          .customSemanticsActionIds!
          .map((id) => CustomSemanticsAction.getAction(id)!.label),
      ['下移'],
    );
    await _dragSkill(tester, 's1', 's2');
    expect(repo.skills.map((s) => s.id), ['s2', 's1', 's3']);
    await _semanticMove(tester, 's1', '上移');
    expect(repo.skills.map((s) => s.id), ['s1', 's2', 's3']);
    final focusContext = tester.element(_dragHandle('s1'));
    Focus.of(focusContext).requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(repo.skills.map((s) => s.id), ['s2', 's1', 's3']);
    await _semanticMove(tester, 's1', '上移');
    expect(repo.skills.map((s) => s.id), ['s1', 's2', 's3']);
    await tester.tap(find.byKey(const ValueKey('skill_enabled_s1')));
    await tester.pumpAndSettle();
    expect(repo.skills.first.enabled, false);
    await tester.tap(find.byKey(const ValueKey('skill_enabled_s1')));
    await tester.pumpAndSettle();
    expect(repo.skills.first.enabled, true);
    await tester.tap(find.text('全部类型'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('生图').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('画面保真'), findsOneWidget);
    expect(find.textContaining('视频技能'), findsNothing);
    expect(find.textContaining('对话技能'), findsNothing);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('过滤列表双向鼠标拖动映射全局位置，隐藏条目保持相对顺序', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = MemorySkillStorage(_sortSkills);
    final repo = await _repository(storage);
    addTearDown(repo.dispose);
    await _pump(tester, SettingsSkillsPage(repository: repo));
    await tester.tap(find.text('全部类型'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('生图').last);
    await tester.pumpAndSettle();
    expect(find.text('隐藏对话一'), findsNothing);
    expect(find.text('隐藏对话二'), findsNothing);

    await _dragSkill(tester, 's1', 's3');
    expect(repo.skills.map((s) => s.id), [
      'hidden1',
      's2',
      'hidden2',
      's3',
      's1',
    ]);
    expect(
      tester.getTopLeft(_dragHandle('s3')).dy,
      lessThan(tester.getTopLeft(_dragHandle('s1')).dy),
    );
    await _dragSkill(tester, 's1', 's2');
    expect(repo.skills.map((s) => s.id), [
      'hidden1',
      's1',
      's2',
      'hidden2',
      's3',
    ]);
    expect(storage.current.map((s) => s.id), repo.skills.map((s) => s.id));
    expect(
      tester.getTopLeft(_dragHandle('s1')).dy,
      lessThan(tester.getTopLeft(_dragHandle('s2')).dy),
    );
    final semantics = tester.ensureSemantics();
    await _semanticMove(tester, 's1', '下移');
    expect(repo.skills.map((s) => s.id), [
      'hidden1',
      's2',
      's1',
      'hidden2',
      's3',
    ]);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('排序、启停与菜单操作均可取消，保存草稿后才执行排序', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = await _repository(MemorySkillStorage(_sortSkills));
    addTearDown(repo.dispose);
    final key = GlobalKey<SettingsSkillsPageState>();
    await _pump(tester, SettingsSkillsPage(key: key, repository: repo));
    await tester.tap(find.text('画面保真'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('skill_name')), '排序前草稿');
    for (final action in ['拖动', '启停', '复制', '删除']) {
      switch (action) {
        case '拖动':
          await _dragSkill(tester, 's1', 's2');
        case '启停':
          await tester.tap(find.byKey(const ValueKey('skill_enabled_s1')));
          await tester.pumpAndSettle();
        default:
          await _skillMenu(tester, 's1', action);
      }
      expect(find.text('技能有未保存的修改'), findsOneWidget);
      await tester.tap(find.text('继续编辑'));
      await tester.pumpAndSettle();
      expect(repo.skills.map((s) => s.id), _sortSkills.map((s) => s.id));
      expect(repo.skills.first.name, '画面保真');
      expect(repo.skills.first.enabled, true);
      expect(
        tester
            .widget<TextBox>(find.byKey(const ValueKey('skill_name')))
            .controller!
            .text,
        '排序前草稿',
      );
      expect(key.currentState!.hasUnsavedChanges, true);
      expect(find.text('删除技能'), findsNothing);
    }
    await _dragSkill(tester, 's1', 's2');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(repo.skills.map((s) => s.id), [
      'hidden1',
      's2',
      's1',
      'hidden2',
      's3',
    ]);
    expect(repo.skills[2].name, '排序前草稿');
    expect(key.currentState!.hasUnsavedChanges, false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('拖动存储失败恢复原顺序，guard 保存失败仍保留草稿', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = await _repository(_FailingStorage(_sortSkills));
    addTearDown(repo.dispose);
    final key = GlobalKey<SettingsSkillsPageState>();
    await _pump(tester, SettingsSkillsPage(key: key, repository: repo));
    await _dragSkill(tester, 's1', 's2');
    expect(repo.skills.map((s) => s.id), _sortSkills.map((s) => s.id));
    expect(
      tester.getTopLeft(_dragHandle('s1')).dy,
      lessThan(tester.getTopLeft(_dragHandle('s2')).dy),
    );
    expect(find.textContaining('磁盘不可写'), findsOneWidget);
    await tester.tap(find.text('画面保真'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('skill_name')), '失败时的草稿');
    await _dragSkill(tester, 's1', 's2');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(repo.skills.map((s) => s.id), _sortSkills.map((s) => s.id));
    expect(repo.skills.first.name, '画面保真');
    expect(key.currentState!.hasUnsavedChanges, true);
    expect(
      tester
          .widget<TextBox>(find.byKey(const ValueKey('skill_name')))
          .controller!
          .text,
      '失败时的草稿',
    );
    expect(find.textContaining('磁盘不可写'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('同位置排序不写存储，异步排序完成前禁用列表操作', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = _PendingStorage();
    final repo = await _repository(storage);
    addTearDown(repo.dispose);
    await _pump(tester, SettingsSkillsPage(repository: repo));
    final list = tester.widget<ReorderableList>(find.byType(ReorderableList));
    list.onReorderItem!(0, 0);
    await tester.pumpAndSettle();
    expect(storage.writes, 0);
    await _dragSkill(tester, 's1', 's2');
    expect(storage.writes, 1);
    expect(repo.skills.map((s) => s.id), _sortSkills.map((s) => s.id));
    expect(
      tester
          .widget<ToggleSwitch>(find.byKey(const ValueKey('skill_enabled_s1')))
          .onChanged,
      isNull,
    );
    expect(
      tester
          .widget<DropDownButton>(
            find.byKey(const ValueKey('skill_actions_s1')),
          )
          .disabled,
      true,
    );
    expect(
      tester
          .widgetList<ReorderableDragStartListener>(
            find.byType(ReorderableDragStartListener),
          )
          .every((listener) => !listener.enabled),
      true,
    );
    list.onReorderItem!(0, 4);
    await tester.pumpAndSettle();
    expect(storage.writes, 1);
    storage.pending.complete();
    await tester.pumpAndSettle();
    expect(repo.skills.map((s) => s.id), [
      'hidden1',
      's2',
      's1',
      'hidden2',
      's3',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未保存编辑可继续或放弃，保存失败阻止离开并显示原因', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = await _repository(_FailingStorage());
    addTearDown(repo.dispose);
    final key = GlobalKey<SettingsSkillsPageState>();
    await _pump(tester, SettingsSkillsPage(key: key, repository: repo));
    await tester.tap(find.textContaining('画面保真').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('skill_name')), '修改名称');
    final stay = key.currentState!.confirmLeave();
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(await stay, false);
    expect(key.currentState!.hasUnsavedChanges, true);
    final save = key.currentState!.confirmLeave();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(await save, false);
    expect(key.currentState!.hasUnsavedChanges, true);
    expect(find.textContaining('磁盘不可写'), findsOneWidget);
    expect(repo.skills.single.name, '画面保真');
    final discard = key.currentState!.confirmLeave();
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();
    expect(await discard, true);
    expect(key.currentState!.hasUnsavedChanges, false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('摘要响应启停，预览来自 core，空技能仍可管理', (tester) async {
    final repo = await _repository();
    addTearDown(repo.dispose);
    var managed = false;
    await _pump(
      tester,
      SkillSummary(
        repository: repo,
        target: SkillTarget.image,
        prompt: '猫',
        onManage: () => managed = true,
      ),
    );
    expect(find.text('技能 1：画面保真'), findsOneWidget);
    await tester.tap(find.text('最终提示词预览'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        composeSkillPrompt(
          prompt: '猫',
          skills: repo.snapshotFor(SkillTarget.image),
        ),
      ),
      findsOneWidget,
    );
    await repo.setEnabled('s1', false);
    await tester.pumpAndSettle();
    expect(find.text('技能：未启用 · 管理技能'), findsOneWidget);
    await tester.tap(find.text('技能：未启用 · 管理技能'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('管理技能'));
    await tester.pumpAndSettle();
    expect(managed, true);
  });

  for (final target in [SkillTarget.image, SkillTarget.video]) {
    testWidgets('${target.label}预览与详情去除用户提示词首尾空白，保留内部空白', (tester) async {
      final repo = await _repository();
      addTearDown(repo.dispose);
      await _pump(
        tester,
        SkillSummary(
          repository: repo,
          target: target,
          prompt: '\n  猫 在 窗边 \t\n',
        ),
      );
      await tester.tap(find.text('最终提示词预览'));
      await tester.pumpAndSettle();
      for (final enabled in [true, false]) {
        await repo.setEnabled(_skill.id, enabled);
        await tester.pumpAndSettle();
        final expected = enabled
            ? '【技能：画面保真】\n提示词：\n保持原主体\n规则：\n避免增加角色\n\n【用户需求】\n猫 在 窗边'
            : '猫 在 窗边';
        expect(
          tester
              .widget<SelectableText>(
                find.descendant(
                  of: find.byType(SkillSummary),
                  matching: find.byType(SelectableText),
                ),
              )
              .data,
          expected,
        );
        await tester.tap(find.text(enabled ? '技能 1：画面保真' : '技能：未启用 · 管理技能'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<SelectableText>(
                find
                    .descendant(
                      of: find.byType(ContentDialog),
                      matching: find.byType(SelectableText),
                    )
                    .last,
              )
              .data,
          expected,
        );
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
      }
    });
  }

  for (final domain in PromptDomain.values) {
    for (final structured in [false, true]) {
      testWidgets('$domain ${structured ? '结构化' : '模板'}润色与迭代使用领域快照，生成中变更保留结果', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(1100, 950));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repo = await _repository();
        addTearDown(repo.dispose);
        await repo.saveSkill(
          const CustomSkill(
            id: 'chat',
            name: '仅对话',
            prompt: 'chat-only',
            targets: {SkillTarget.chat},
          ),
        );
        final providers = ProviderRepository(
          storage: MemoryProviderStorage(),
          connectionTester: StubProviderConnectionTester(),
        );
        await providers.load();
        await providers.updateProvider(
          providers.activeProviderId,
          baseUrl: 'https://api.example.com/v1',
          apiKey: 'test',
          chatModel: 'gpt-4o',
        );
        addTearDown(providers.dispose);
        final client = _EnhanceClient();
        addTearDown(client.close);
        await _pump(
          tester,
          SizedBox(
            width: 680,
            height: 720,
            child: structured
                ? PromptBuilderPanel(
                    domain: domain,
                    skillRepository: repo,
                    providerRepository: providers,
                    chatClient: client,
                    onApply: (_) {},
                  )
                : PromptAssistPanel(
                    domain: domain,
                    draftPrompt: '猫',
                    skillRepository: repo,
                    providerRepository: providers,
                    chatClient: client,
                    onApply: (_) {},
                  ),
          ),
        );
        if (structured) {
          await tester.tap(
            find.text(getPromptDimensions(domain).first.options.first.label),
          );
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('✨ AI 润色'));
        await tester.pump();
        expect(client.requests.single.first['content'], contains('保持原主体'));
        expect(
          client.requests.single.first['content'],
          isNot(contains('chat-only')),
        );
        await repo.saveSkill(_skill.copyWith(prompt: '最新约束'));
        await tester.pump();
        expect(find.text('技能已变更，建议重新润色'), findsOneWidget);
        expect(find.text('流式结果'), findsOneWidget);
        client.pending.single.complete(
          const ChatStreamResult(content: '保留的结果'),
        );
        await tester.pumpAndSettle();
        expect(find.text('保留的结果'), findsOneWidget);
        expect(find.text('技能已变更，建议重新润色'), findsOneWidget);
        for (final instruction in kPromptRefineInstructions) {
          await tester.tap(find.text(instruction));
          await tester.pump();
          expect(client.requests.last.first['content'], contains('最新约束'));
          expect(client.requests.last.last['content'], contains(instruction));
          expect(find.text('技能已变更，建议重新润色'), findsNothing);
          client.pending.last.complete(const ChatStreamResult(content: '迭代结果'));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('三类历史展示保存快照，旧媒体记录隐藏入口', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const snapshots = [
      SkillSnapshot(
        id: 'deleted',
        name: '已删除技能',
        prompt: '历史约束',
        rules: '历史规则',
      ),
    ];
    await _pump(
      tester,
      MessageBubble(
        message: ChatMessage(
          id: 'm',
          createdAt: 1,
          role: ChatRole.user,
          content: '需求',
          appliedSkills: snapshots,
        ),
      ),
    );
    await tester.tap(find.text('查看技能快照'));
    await tester.pumpAndSettle();
    expect(find.text('历史约束'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await _pump(
      tester,
      ImageTimeline(
        items: [
          ImageItem(
            id: 'i',
            createdAt: 1,
            mode: ImageGenMode.text,
            prompt: '原文',
            finalPrompt: '最终图片提示',
            appliedSkills: snapshots,
          ),
        ],
        loadBytes: (_) async => null,
        onPreview: (_, _, _) {},
        onSave: (_, _, _) {},
      ),
    );
    await tester.tap(find.text('查看技能快照'));
    await tester.pumpAndSettle();
    expect(find.text('最终图片提示'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await _pump(
      tester,
      VideoQueue(
        items: [
          VideoItem(
            id: 'v',
            createdAt: 1,
            mode: VideoGenMode.text,
            prompt: '原文',
            finalPrompt: '最终视频提示',
            appliedSkills: snapshots,
            status: VideoItemStatus.error,
          ),
        ],
        onOpen: (_) {},
        onSave: (_) {},
        onResume: (_) {},
        onAbandon: (_) {},
      ),
    );
    await tester.tap(find.text('查看技能快照'));
    await tester.pumpAndSettle();
    expect(find.text('最终视频提示'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await _pump(
      tester,
      ImageTimeline(
        items: [
          ImageItem(
            id: 'old',
            createdAt: 1,
            mode: ImageGenMode.text,
            prompt: '旧原文',
          ),
        ],
        loadBytes: (_) async => null,
        onPreview: (_, _, _) {},
        onSave: (_, _, _) {},
      ),
    );
    expect(find.text('查看技能快照'), findsNothing);
  });
}
