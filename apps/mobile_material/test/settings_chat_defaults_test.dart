import 'dart:async';

import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_material/app/theme_controller.dart';
import 'package:mobile_material/pages/settings/settings_chat_defaults_tab.dart';
import 'package:mobile_material/pages/settings/settings_page.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _LockedPortalPrefs extends HiddenPortalPrefs {
  @override
  Future<void> ensureLoaded() async {}
}

class _RecordingStorage extends MemoryChatDefaultsStorage {
  _RecordingStorage([super.initial]);

  final attempts = <ChatDefaults>[];
  Completer<void>? pending;

  @override
  Future<void> save(ChatDefaults defaults) async {
    attempts.add(defaults);
    await pending?.future;
    await super.save(defaults);
  }
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

TextField _input(WidgetTester tester, String label) =>
    tester.widget<TextField>(_field(label));

Future<void> _pumpTab(
  WidgetTester tester,
  ChatDefaultsRepository repository,
) async {
  // 让全部字段可见，忙态下仍另行检查滚动能力。
  await tester.binding.setSurfaceSize(const Size(600, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildMaterialLightTheme(),
      home: Scaffold(body: SettingsChatDefaultsTab(repository: repository)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await _showAction(tester, find.text('保存默认'));
  await tester.tap(find.text('保存默认'));
  await tester.pumpAndSettle();
}

Future<void> _showAction(WidgetTester tester, Finder action) async {
  await tester.scrollUntilVisible(
    action,
    250,
    scrollable: find
        .descendant(
          of: find.descendant(
            of: find.byType(SettingsChatDefaultsTab),
            matching: find.byType(ListView),
          ),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(action);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('实际设置 Tab 失焦切至日志再返回，保留草稿并区分同步与冲突', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'AI Studio',
      packageName: 'studio.test',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    final providers = ProviderRepository(storage: MemoryProviderStorage());
    final appearance = AppearanceRepository(storage: MemoryAppearanceStorage());
    final defaults = ChatDefaultsRepository(
      storage: MemoryChatDefaultsStorage(),
    );
    final chats = ChatSessionRepository(storage: MemoryChatSessionStorage());
    final images = ImageSessionRepository(storage: MemoryImageSessionStorage());
    final videos = VideoSessionRepository(storage: MemoryVideoSessionStorage());
    final logs = AppLogRepository(storage: MemoryAppLogStorage());
    final skills = SkillRepository(storage: MemorySkillStorage());
    final portal = _LockedPortalPrefs();
    final theme = ThemeController();
    final generation = GenerationRuntime();
    await Future.wait([
      providers.load(),
      appearance.load(),
      defaults.load(),
      chats.load(),
      images.load(),
      videos.load(),
      logs.load(),
      skills.load(),
      portal.ensureLoaded(),
    ]);
    addTearDown(() {
      for (final notifier in [
        providers,
        appearance,
        defaults,
        chats,
        images,
        videos,
        logs,
        skills,
        portal,
        theme,
        generation,
      ]) {
        notifier.dispose();
      }
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildMaterialLightTheme(),
        home: SettingsPage(
          themeController: theme,
          providerRepository: providers,
          chatDefaultsRepository: defaults,
          appearanceRepository: appearance,
          appLogRepository: logs,
          skillRepository: skills,
          hiddenPortalPrefs: portal,
          generation: generation,
          initialTabIndex: 1,
          dataBackupService: DataBackupService(
            providers: providers,
            appearance: appearance,
            chatDefaults: defaults,
            chatSessions: chats,
            imageSessions: images,
            videoSessions: videos,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> switchTab(String label) async {
      final tab = find.widgetWithText(Tab, label);
      await tester.ensureVisible(tab);
      await tester.tap(tab);
      await tester.pumpAndSettle();
    }

    final state = tester.state(find.byType(SettingsChatDefaultsTab));
    await switchTab('日志');
    await defaults.save(const ChatDefaults(systemPrompt: '无草稿时同步'));
    await tester.pumpAndSettle();
    await switchTab('对话');
    expect(_input(tester, '系统提示').controller!.text, '无草稿时同步');
    expect(tester.state(find.byType(SettingsChatDefaultsTab)), same(state));

    await tester.enterText(_field('系统提示'), '切换后仍在的草稿');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await switchTab('日志');
    await defaults.save(const ChatDefaults(systemPrompt: '外部更新'));
    await tester.pumpAndSettle();
    await switchTab('对话');
    expect(_input(tester, '系统提示').controller!.text, '切换后仍在的草稿');
    expect(tester.state(find.byType(SettingsChatDefaultsTab)), same(state));
    expect(find.textContaining('当前草稿已保留'), findsOneWidget);
    await _save(tester);
    expect(find.text('覆盖最新配置？'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(defaults.defaults.systemPrompt, '外部更新');
    await tester.ensureVisible(find.widgetWithText(OutlinedButton, '取消'));
    await tester.tap(find.widgetWithText(OutlinedButton, '取消'));
    await tester.pumpAndSettle();
    expect(_input(tester, '系统提示').controller!.text, '外部更新');
    expect(find.textContaining('当前草稿已保留'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final spec in [
    (label: 'Max Tokens', min: 0, max: 200000),
    (label: '超时（秒）', min: 1, max: 600),
    (label: '最大轮数', min: 1, max: 200),
    (label: '最大字符数', min: 1, max: 500000),
  ]) {
    testWidgets('${spec.label} 拒绝空值、格式和越界，保留原文且支持合法边界', (tester) async {
      final storage = _RecordingStorage(
        const ChatDefaults(contextMaxCharsEnabled: true),
      );
      final repository = ChatDefaultsRepository(storage: storage);
      await repository.load();
      addTearDown(repository.dispose);
      await _pumpTab(tester, repository);
      for (final invalid in [
        '',
        '-1',
        '1.5',
        'abc',
        '0x10',
        '${spec.max + 1}',
        if (spec.min > 0) '0',
      ]) {
        await tester.enterText(_field(spec.label), invalid);
        await _save(tester);
        expect(_input(tester, spec.label).controller!.text, invalid);
        expect(
          _input(tester, spec.label).decoration!.errorText,
          '请输入 ${spec.min}～${spec.max} 之间的整数',
        );
        expect(storage.attempts, isEmpty);
        expect(find.text('已保存对话默认'), findsNothing);
      }
      for (final boundary in [spec.min, spec.max]) {
        await tester.enterText(_field(spec.label), '$boundary');
        await _save(tester);
        expect(_input(tester, spec.label).decoration!.errorText, isNull);
        expect(_input(tester, spec.label).controller!.text, '$boundary');
      }
      expect(storage.attempts.length, 2);
    });
  }

  testWidgets('关闭裁剪字段清除错误且不阻止保存，沿用最新仓库值', (tester) async {
    final storage = _RecordingStorage(
      const ChatDefaults(
        contextMaxTurns: 37,
        contextMaxCharsEnabled: true,
        contextMaxChars: 45678,
      ),
    );
    final repository = ChatDefaultsRepository(storage: storage);
    await repository.load();
    addTearDown(repository.dispose);
    await _pumpTab(tester, repository);
    await tester.enterText(_field('最大轮数'), '');
    await tester.enterText(_field('最大字符数'), '-1');
    await _save(tester);
    expect(storage.attempts, isEmpty);
    for (final label in ['按轮数裁剪上下文', '启用字符预算']) {
      await tester.tap(find.widgetWithText(SwitchListTile, label));
      await tester.pumpAndSettle();
    }
    expect(_input(tester, '最大轮数').decoration!.errorText, isNull);
    expect(_input(tester, '最大字符数').decoration!.errorText, isNull);
    await repository.save(
      repository.defaults.copyWith(contextMaxTurns: 42, contextMaxChars: 54321),
    );
    await tester.pumpAndSettle();
    await _save(tester);
    await repository.save(
      repository.defaults.copyWith(contextMaxTurns: 43, contextMaxChars: 54322),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('覆盖保存'));
    await tester.pumpAndSettle();
    expect(repository.defaults.contextTrimEnabled, isFalse);
    expect(repository.defaults.contextMaxCharsEnabled, isFalse);
    expect(repository.defaults.contextMaxTurns, 43);
    expect(repository.defaults.contextMaxChars, 54322);
    expect(_input(tester, '最大轮数').controller!.text, '43');
    expect(_input(tester, '最大字符数').controller!.text, '54322');
  });

  for (final reset in [false, true]) {
    testWidgets('${reset ? '恢复' : '保存'}期间锁定全部编辑并防重入，失败保留草稿且可重试', (
      tester,
    ) async {
      const original = ChatDefaults(
        systemPrompt: '已保存',
        temperature: 1.2,
        contextMaxCharsEnabled: true,
      );
      final storage = _RecordingStorage(original);
      final repository = ChatDefaultsRepository(storage: storage);
      await repository.load();
      addTearDown(repository.dispose);
      await _pumpTab(tester, repository);
      await tester.enterText(_field('系统提示'), '待保存草稿');
      await tester.pumpAndSettle();
      final oldSlider = tester.widget<Slider>(find.byType(Slider));
      final oldSwitches = tester
          .widgetList<SwitchListTile>(find.byType(SwitchListTile))
          .toList();
      final save = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '保存默认'))
          .onPressed!;
      final restore = tester
          .widget<TextButton>(find.widgetWithText(TextButton, '恢复推荐值'))
          .onPressed!;
      storage.pending = Completer<void>();
      if (reset) {
        restore();
        restore();
        await tester.pumpAndSettle();
        expect(find.text('恢复推荐值？'), findsOneWidget);
        expect(storage.attempts, isEmpty);
        await tester.tap(find.widgetWithText(FilledButton, '恢复'));
      } else {
        save();
        save();
      }
      await tester.pumpAndSettle();
      expect(storage.attempts.length, 1);
      expect(repository.defaults, original);
      for (final field in tester.widgetList<TextField>(
        find.byType(TextField),
      )) {
        expect(field.enabled, isFalse);
      }
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
      for (final toggle in tester.widgetList<SwitchListTile>(
        find.byType(SwitchListTile),
      )) {
        expect(toggle.onChanged, isNull);
      }
      // 已排队的旧回调也不能改草稿或启动第二次持久化。
      oldSlider.onChanged!(0.1);
      for (final toggle in oldSwitches) {
        toggle.onChanged!(!toggle.value);
      }
      save();
      restore();
      await tester.pump();
      expect(storage.attempts.length, 1);
      expect(tester.widget<Slider>(find.byType(Slider)).value, 1.2);
      expect(
        tester
            .widgetList<SwitchListTile>(find.byType(SwitchListTile))
            .every((toggle) => toggle.value),
        isTrue,
      );

      // 禁用的是表单输入，ListView 仍响应滚动。
      await tester.binding.setSurfaceSize(const Size(600, 500));
      await tester.pumpAndSettle();
      final scrollable = find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;
      final before = position.pixels;
      await tester.drag(find.byType(ListView), const Offset(0, -250));
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(before));

      storage.pending!.completeError(StateError('测试持久化失败'));
      await tester.pumpAndSettle();
      expect(repository.defaults, original);
      expect(_input(tester, '系统提示').controller!.text, '待保存草稿');
      expect(_input(tester, '系统提示').enabled, isTrue);
      expect(find.textContaining('测试持久化失败'), findsOneWidget);
      storage.pending = null;
      await _save(tester);
      expect(storage.attempts.length, 2);
      expect(repository.defaults.systemPrompt, '待保存草稿');
      expect(find.text('覆盖最新配置？'), findsNothing);
    });
  }

  testWidgets('恢复确认返回时子页已销毁，不再保存或更新已销毁状态', (tester) async {
    final storage = _RecordingStorage();
    final repository = ChatDefaultsRepository(storage: storage);
    await repository.load();
    addTearDown(repository.dispose);
    final showTab = ValueNotifier(true);
    addTearDown(showTab.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildMaterialLightTheme(),
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: showTab,
            builder: (context, visible, child) => visible
                ? SettingsChatDefaultsTab(repository: repository)
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _showAction(tester, find.text('恢复推荐值'));
    await tester.tap(find.text('恢复推荐值'));
    await tester.pumpAndSettle();
    showTab.value = false;
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '恢复'));
    await tester.pumpAndSettle();
    expect(storage.attempts, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
