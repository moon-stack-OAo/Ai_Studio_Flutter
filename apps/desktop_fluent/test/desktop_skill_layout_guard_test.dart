import 'dart:async';

import 'package:core/core.dart';
import 'package:desktop_fluent/app/theme_controller.dart';
import 'package:desktop_fluent/main.dart';
import 'package:desktop_fluent/pages/image/widgets/image_composer.dart';
import 'package:desktop_fluent/pages/settings/settings_about_page.dart';
import 'package:desktop_fluent/pages/settings/settings_skills_page.dart';
import 'package:desktop_fluent/pages/settings/settings_shell.dart';
import 'package:desktop_fluent/shell/app_section.dart';
import 'package:desktop_fluent/pages/video/widgets/video_composer.dart';
import 'package:desktop_fluent/shell/window_close_coordinator.dart';
import 'package:desktop_fluent/widgets/skill_summary.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

const _skill = CustomSkill(
  id: 'layout-skill',
  name: '用于验证窄窗口长名称换行与截断的自定义技能名称',
  prompt: '保持主体',
  rules: '保持原始意图',
  targets: {SkillTarget.chat, SkillTarget.image, SkillTarget.video},
);

class _ControlledStorage extends MemorySkillStorage {
  _ControlledStorage() : super([_skill]);
  Completer<void>? pending;
  bool fail = false;

  @override
  Future<void> save(List<CustomSkill> skills) async {
    await pending?.future;
    if (fail) throw StateError('保存失败，磁盘不可写');
    await super.save(skills);
  }
}

class _Fixture {
  _Fixture(this.skills);

  final SkillRepository skills;
  final providers = ProviderRepository(
    storage: MemoryProviderStorage(),
    connectionTester: StubProviderConnectionTester(),
  );
  final chats = ChatSessionRepository(storage: MemoryChatSessionStorage());
  final images = ImageSessionRepository(storage: MemoryImageSessionStorage());
  final videos = VideoSessionRepository(storage: MemoryVideoSessionStorage());
  final defaults = ChatDefaultsRepository(storage: MemoryChatDefaultsStorage());
  final logs = AppLogRepository(storage: MemoryAppLogStorage());
  final appearance = AppearanceRepository(storage: MemoryAppearanceStorage());
  final theme = ThemeController();
  final generation = GenerationRuntime();

  Future<void> load() async {
    await Future.wait([
      skills.load(),
      providers.load(),
      chats.load(),
      images.load(),
      videos.load(),
      defaults.load(),
      logs.load(),
      appearance.load(),
    ]);
  }

  late final backup = DataBackupService(
    providers: providers,
    appearance: appearance,
    chatDefaults: defaults,
    chatSessions: chats,
    imageSessions: images,
    videoSessions: videos,
    skillRepository: skills,
  );

  Widget get app => buildApp();

  Widget buildApp({WindowCloseCoordinator? coordinator}) => AiStudioApp(
    closeCoordinator: coordinator,
    skillRepository: skills,
    themeController: theme,
    providerRepository: providers,
    sessionRepository: chats,
    imageSessionRepository: images,
    videoSessionRepository: videos,
    chatDefaultsRepository: defaults,
    appLogRepository: logs,
    dataBackupService: backup,
    generation: generation,
    showBrandIntro: false,
  );

  void dispose() {
    skills.dispose();
    providers.dispose();
    chats.dispose();
    images.dispose();
    videos.dispose();
    defaults.dispose();
    logs.dispose();
    appearance.dispose();
    theme.dispose();
    generation.dispose();
  }
}

class _InteractionCoordinator extends WindowCloseCoordinator {
  _InteractionCoordinator(_Fixture fixture, VoidCallback onQuit)
    : super(
        appearanceRepository: fixture.appearance,
        navigatorKey: GlobalKey<NavigatorState>(),
        onBeforeQuit: onQuit,
      );

  int preparations = 0;
  Completer<void>? restoring;

  @override
  Future<void> prepareForInteraction() async {
    preparations++;
    await restoring?.future;
  }
}

class _DelayedBackup extends DataBackupService {
  _DelayedBackup(_Fixture fixture)
    : super(
        providers: fixture.providers,
        appearance: fixture.appearance,
        chatDefaults: fixture.defaults,
        chatSessions: fixture.chats,
        imageSessions: fixture.images,
        videoSessions: fixture.videos,
        skillRepository: fixture.skills,
      );

  final requests = <Completer<StorageUsageEstimate>>[];

  @override
  Future<StorageUsageEstimate> estimateStorageUsage() {
    final request = Completer<StorageUsageEstimate>();
    requests.add(request);
    return request.future;
  }
}

StorageUsageEstimate _usage(int skills) => StorageUsageEstimate(
  chatSessionCount: 0,
  imageSessionCount: 0,
  videoSessionCount: 0,
  chatMessageCount: 0,
  providerCount: 0,
  logEntryCount: 0,
  imageCacheBytes: 0,
  videoCacheBytes: 0,
  approxJsonBytes: 0,
  skillCount: skills,
);

Finder _skillCount(int count, {bool skipOffstage = true}) =>
    find.textContaining(RegExp('· 技能 $count\$'), skipOffstage: skipOffstage);

Future<void> _showUsage(WidgetTester tester, Finder summary) async {
  await tester.scrollUntilVisible(
    summary,
    200,
    scrollable: find
        .descendant(
          of: find.byType(SettingsAboutPage),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

Future<void> _openEditor(WidgetTester tester) async {
  await tester.tap(find.byTooltip('设置'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('自定义技能').first);
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining(_skill.name).first);
  await tester.pumpAndSettle();
}

void main() {
  for (final dark in [false, true]) {
    for (final scale in [AppFontScale.smaller, AppFontScale.larger]) {
      testWidgets('960×640 设置分类在${dark ? '深色' : '浅色'} ${scale.label}字号下可用', (
        tester,
      ) async {
        // 实际 960px 窗口扣除 56px 主导航后的设置区宽度。
        await tester.binding.setSurfaceSize(const Size(904, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        PackageInfo.setMockInitialValues(
          appName: 'AI Studio',
          packageName: 'studio.test',
          version: '1.0.8',
          buildNumber: '1',
          buildSignature: '',
        );
        final fixture = _Fixture(
          SkillRepository(storage: MemorySkillStorage([_skill])),
        );
        await fixture.load();
        final mcp = McpServerRepository(
          storage: MemoryMcpServerStorage([
            const McpServerConfig(
              id: 'mcp',
              displayName: '排版测试 Server',
              baseUrl: 'https://example.com/mcp',
            ),
          ]),
          secretStore: MemorySecretStore(),
        );
        await mcp.load();
        var category = SettingsCategory.providers;
        await tester.pumpWidget(
          FluentApp(
            theme: dark
                ? buildFluentDarkTheme(fontScale: scale)
                : buildFluentLightTheme(fontScale: scale),
            home: StatefulBuilder(
              builder: (context, setLocal) => SettingsShell(
                category: category,
                onCategoryChanged: (value) => setLocal(() => category = value),
                themeController: fixture.theme,
                appearanceRepository: fixture.appearance,
                providerRepository: fixture.providers,
                chatDefaultsRepository: fixture.defaults,
                appLogRepository: fixture.logs,
                dataBackupService: fixture.backup,
                generation: fixture.generation,
                skillRepository: fixture.skills,
                mcpServerRepository: mcp,
                mcpSessionFactory: HttpSseMcpSessionFactory(
                  secretStoreAuthBuilder: (_) => NoneMcpAuth(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final item in SettingsCategory.visibleByDefault) {
          await tester.tap(find.text(item.label).first);
          await tester.pumpAndSettle();
          if (item == SettingsCategory.skills) {
            await tester.tap(find.text(_skill.name));
            await tester.pumpAndSettle();
          }
          final page = find.byKey(ValueKey('settings_page_${item.name}'));
          final title = switch (item) {
            SettingsCategory.providers => '编辑提供商',
            SettingsCategory.mcp => '编辑 MCP Server',
            SettingsCategory.chatDefaults => '对话默认',
            SettingsCategory.skills => '编辑技能',
            SettingsCategory.appearance => '外观',
            SettingsCategory.logs => '运行日志',
            SettingsCategory.about => '关于与更新',
            SettingsCategory.lab => throw StateError('隐藏分类不参与测试'),
          };
          final titleWidget = tester.widget<Text>(
            find.descendant(of: page, matching: find.text(title)),
          );
          expect(
            titleWidget.style?.fontSize,
            closeTo(20 * scale.factor, 0.001),
          );
          expect(titleWidget.style?.fontWeight, FontWeight.w600);
          final inputs = find.descendant(
            of: page,
            matching: find.byType(EditableText),
          );
          if (inputs.evaluate().isNotEmpty) {
            expect(
              tester.widget<EditableText>(inputs.first).style.fontSize,
              closeTo(13 * scale.factor, 0.001),
              reason: '${item.label} 输入文字应统一缩放',
            );
          }
          expect(
            tester.takeException(),
            isNull,
            reason: '${item.label} 不应布局溢出',
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
        mcp.dispose();
        fixture.dispose();
      });
    }
  }

  testWidgets('规则编辑区随窗口增高填充剩余空间，保存栏固定可见', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final skills = SkillRepository(storage: MemorySkillStorage([_skill]));
    await skills.load();
    addTearDown(skills.dispose);
    await tester.pumpWidget(
      FluentApp(
        theme: buildFluentLightTheme(),
        home: SettingsSkillsPage(repository: skills),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(_skill.name));
    await tester.pumpAndSettle();
    final rules = find.byKey(const ValueKey('skill_rules'));
    final initial = tester.getRect(rules);
    expect(initial.height, greaterThan(180));
    final formScroll = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    expect(formScroll.maxScrollExtent, 0, reason: '表单能完整显示时不应产生多余滚动范围');
    expect(find.text('保存技能').hitTestable(), findsOneWidget);
    await tester.binding.setSurfaceSize(const Size(1100, 1400));
    await tester.pumpAndSettle();
    final expanded = tester.getRect(rules);
    expect(expanded.height - initial.height, closeTo(300, 1));
    expect(expanded.top, closeTo(initial.top, 1));
    expect(formScroll.maxScrollExtent, 0);
    expect(find.text('保存技能').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('托盘退出仅在有草稿时等待窗口恢复，再确认；取消后可重试', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = _Fixture(
      SkillRepository(storage: MemorySkillStorage([_skill])),
    );
    await fixture.load();
    var quits = 0;
    final coordinator = _InteractionCoordinator(fixture, () => quits++);
    await tester.pumpWidget(fixture.buildApp(coordinator: coordinator));
    await tester.pumpAndSettle();
    await _openEditor(tester);
    // 有编辑器但无草稿时，退出 guard 不唤起窗口、不显示对话框。
    expect(await coordinator.onConfirmQuit!(), true);
    expect(coordinator.preparations, 0);
    expect(find.text('技能有未保存的修改'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('skill_name')), '托盘中的草稿');
    coordinator.restoring = Completer<void>();
    final quitting = coordinator.quitApp();
    await tester.pumpAndSettle();
    expect(coordinator.preparations, 1);
    expect(find.text('技能有未保存的修改'), findsNothing);
    final page = tester.state<SettingsSkillsPageState>(
      find.byType(SettingsSkillsPage),
    );
    expect(await page.confirmLeave(), false);
    coordinator.restoring!.complete();
    await tester.pumpAndSettle();
    expect(find.text('技能有未保存的修改'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    await quitting;
    expect(quits, 0);
    expect(page.hasUnsavedChanges, true);

    coordinator.restoring = null;
    final retry = coordinator.quitApp();
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();
    await retry;
    expect(quits, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(coordinator.onConfirmQuit, isNull);
    fixture.dispose();
  });

  testWidgets('保活关于页在隐藏期间响应技能新增、编辑、删除，重新显示时数量最新', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = _Fixture(
      SkillRepository(storage: MemorySkillStorage([_skill])),
    );
    await fixture.load();
    await tester.pumpWidget(fixture.app);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关于与更新').first);
    await tester.pumpAndSettle();
    await _showUsage(tester, _skillCount(1));
    final aboutState = tester.state(find.byType(SettingsAboutPage));
    await tester.tap(find.text('自定义技能').first);
    await tester.pumpAndSettle();
    await fixture.skills.saveSkill(_skill.copyWith(id: 'second', name: '新增技能'));
    await tester.pumpAndSettle();
    expect(_skillCount(2, skipOffstage: false), findsOneWidget);
    await fixture.skills.saveSkill(_skill.copyWith(id: 'second', name: '编辑技能'));
    await tester.pumpAndSettle();
    expect(_skillCount(2, skipOffstage: false), findsOneWidget);
    await fixture.skills.deleteSkill('second');
    await tester.pumpAndSettle();
    expect(_skillCount(1, skipOffstage: false), findsOneWidget);
    await tester.tap(find.text('关于与更新').first);
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(SettingsAboutPage)), same(aboutState));
    expect(_skillCount(1), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('存储估算乱序完成不覆盖新结果，仓库替换与销毁正确解绑', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = _Fixture(
      SkillRepository(storage: MemorySkillStorage([_skill])),
    );
    await fixture.load();
    final backup = _DelayedBackup(fixture);
    final replacement = SkillRepository(storage: MemorySkillStorage());
    await replacement.load();
    Widget about(SkillRepository skills, DataBackupService service) =>
        FluentApp(
          theme: buildFluentLightTheme(),
          home: SettingsAboutPage(
            appearanceRepository: fixture.appearance,
            skillRepository: skills,
            dataBackupService: service,
            packageInfo: PackageInfo(
              appName: 'AI Studio',
              packageName: 'desktop_fluent',
              version: '1.0.0',
              buildNumber: '1',
            ),
          ),
        );
    await tester.pumpWidget(about(fixture.skills, backup));
    await tester.pumpAndSettle();
    await _showUsage(tester, find.text('正在估算本地占用…'));
    expect(backup.requests, hasLength(1));
    await fixture.skills.saveSkill(_skill.copyWith(id: 'second'));
    await tester.pumpAndSettle();
    expect(backup.requests, hasLength(2));
    backup.requests[1].complete(_usage(2));
    await tester.pumpAndSettle();
    expect(_skillCount(2), findsOneWidget);
    backup.requests[0].complete(_usage(1));
    await tester.pumpAndSettle();
    expect(_skillCount(2), findsOneWidget);
    // 旧请求失败也不能把较新的成功结果清空。
    await fixture.skills.setEnabled(_skill.id, false);
    await fixture.skills.setEnabled(_skill.id, true);
    backup.requests[3].complete(_usage(2));
    await tester.pumpAndSettle();
    backup.requests[2].completeError(StateError('旧估算失败'));
    await tester.pumpAndSettle();
    expect(_skillCount(2), findsOneWidget);
    await tester.pumpWidget(about(replacement, backup));
    await tester.pumpAndSettle();
    expect(backup.requests, hasLength(5));
    await fixture.skills.deleteSkill('second');
    await tester.pumpAndSettle();
    expect(backup.requests, hasLength(5));
    backup.requests[4].complete(_usage(0));
    await tester.pumpAndSettle();
    expect(_skillCount(0), findsOneWidget);
    await replacement.saveSkill(_skill);
    await tester.pumpAndSettle();
    expect(backup.requests, hasLength(6));
    final newBackup = _DelayedBackup(fixture);
    await tester.pumpWidget(about(replacement, newBackup));
    await tester.pumpAndSettle();
    expect(newBackup.requests, hasLength(1));
    newBackup.requests.single.complete(_usage(1));
    await tester.pumpAndSettle();
    backup.requests[5].complete(_usage(999));
    await tester.pumpAndSettle();
    expect(_skillCount(1), findsOneWidget);
    await replacement.setEnabled(_skill.id, false);
    await tester.pumpAndSettle();
    expect(newBackup.requests, hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
    newBackup.requests[1].complete(_usage(1));
    await replacement.deleteSkill(_skill.id);
    await tester.pumpAndSettle();
    expect(newBackup.requests, hasLength(2));
    expect(tester.takeException(), isNull);
    replacement.dispose();
    fixture.dispose();
  });

  for (final dark in [false, true]) {
    testWidgets('960×640 ${dark ? '深色' : '浅色'}大字号下三类技能摘要与媒体预览不溢出', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(960, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fixture = _Fixture(
        SkillRepository(
          storage: MemorySkillStorage([
            for (var i = 0; i < 8; i++)
              _skill.copyWith(id: 's$i', name: '${_skill.name} $i'),
          ]),
        ),
      );
      await fixture.load();
      await fixture.providers.updateProvider(
        fixture.providers.activeProviderId,
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'test',
        chatModel: 'gpt-4o',
        imageModel: 'gpt-image-1',
        videoModel: 'sora-2',
      );
      await fixture.theme.setFontScale(AppFontScale.larger);
      if (dark) await fixture.theme.setPreference(ThemePreference.dark);
      await tester.pumpWidget(fixture.app);
      await tester.pumpAndSettle();
      expect(find.byType(SkillSummary), findsOneWidget);
      expect(
        tester.getSize(find.byType(SkillSummary)).height,
        lessThanOrEqualTo(64),
      );
      expect(tester.takeException(), isNull);

      for (final video in [false, true]) {
        await tester.tap(find.byTooltip(video ? '生视频' : '生图'));
        await tester.pumpAndSettle();
        final composer = video
            ? find.byType(VideoComposer)
            : find.byType(ImageComposer);
        final prompt = find
            .descendant(of: composer, matching: find.byType(TextBox))
            .first;
        await tester.enterText(prompt, List.filled(80, '很长的原始提示词').join(' '));
        await tester.pumpAndSettle();
        final scrollable = find
            .descendant(of: composer, matching: find.byType(Scrollable))
            .first;
        final summary = find.descendant(
          of: composer,
          matching: find.byType(SkillSummary),
        );
        await tester.scrollUntilVisible(summary, 200, scrollable: scrollable);
        await tester.pumpAndSettle();
        expect(tester.getSize(summary).width, lessThanOrEqualTo(272));
        await tester.ensureVisible(find.text('最终提示词预览'));
        await tester.tap(find.text('最终提示词预览'));
        await tester.pumpAndSettle();
        expect(find.text(video ? '创建任务' : '生成').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }

      await _openEditor(tester);
      final card = tester.getRect(find.byKey(const ValueKey('skill_card_s0')));
      expect(card.width, lessThanOrEqualTo(300));
      for (final key in [
        'skill_drag_s0',
        'skill_enabled_s0',
        'skill_actions_s0',
      ]) {
        final control = find.byKey(ValueKey(key));
        expect(control.hitTestable(), findsOneWidget);
        final rect = tester.getRect(control);
        expect(rect.left, greaterThanOrEqualTo(card.left));
        expect(rect.right, lessThanOrEqualTo(card.right));
      }
      final name = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('skill_card_s0')),
          matching: find.text('${_skill.name} 0'),
        ),
      );
      expect(name.maxLines, 2);
      expect(name.overflow, TextOverflow.ellipsis);
      expect(find.text('复制'), findsNothing);
      expect(find.text('删除'), findsNothing);
      expect(find.text('上移'), findsNothing);
      expect(find.text('下移'), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('skill_name')), '小窗口编辑');
      await tester.pumpAndSettle();
      final editor = find
          .descendant(
            of: find.byType(SettingsSkillsPage),
            matching: find.byType(CustomScrollView),
          )
          .last;
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('skill_rules')),
        200,
        scrollable: find
            .descendant(of: editor, matching: find.byType(Scrollable))
            .first,
      );
      await tester.pumpAndSettle();
      expect(
        find.text('保存技能').hitTestable(),
        findsOneWidget,
        reason:
            '保存区域 ${tester.getRect(find.text('保存技能'))}，编辑区 ${tester.getRect(editor)}',
      );
      expect(find.text('有未保存的修改').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    });
  }

  testWidgets('异步保存期间禁止导航，失败保留草稿且允许重试成功离开', (tester) async {
    await tester.binding.setSurfaceSize(const Size(960, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = _ControlledStorage();
    final fixture = _Fixture(SkillRepository(storage: storage));
    await fixture.load();
    await tester.pumpWidget(fixture.app);
    await tester.pumpAndSettle();
    await _openEditor(tester);
    await tester.enterText(find.byKey(const ValueKey('skill_name')), '待保存草稿');
    storage.pending = Completer<void>();
    storage.fail = true;
    await tester.tap(find.byTooltip('对话'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextBox>(find.byKey(const ValueKey('skill_name'))).enabled,
      false,
    );
    await tester.tap(find.text('对话默认'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('skill_name')), findsOneWidget);
    final page = tester.state<SettingsSkillsPageState>(
      find.byType(SettingsSkillsPage),
    );
    final concurrentLeave = page.confirmLeave();
    expect(await concurrentLeave, false);
    expect(find.text('技能有未保存的修改'), findsNothing);
    storage.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('磁盘不可写'), findsOneWidget);
    expect(
      tester
          .widget<TextBox>(find.byKey(const ValueKey('skill_name')))
          .controller!
          .text,
      '待保存草稿',
    );
    expect(page.hasUnsavedChanges, true);
    expect(fixture.skills.skills.single.name, _skill.name);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('技能有未保存的修改'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    storage.fail = false;
    storage.pending = null;
    await tester.tap(find.text('对话默认'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('skill_name')), findsNothing);
    expect(fixture.skills.skills.single.name, '待保存草稿');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });
}
