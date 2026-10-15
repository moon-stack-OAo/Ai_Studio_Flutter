import 'dart:async';

import 'package:core/core.dart';
import 'package:desktop_fluent/pages/settings/settings_chat_defaults_page.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

class _ControlledStorage implements ChatDefaultsStorage {
  _ControlledStorage(this.current);

  ChatDefaults current;
  final writes = <ChatDefaults>[];
  Completer<void>? nextSave;
  bool failNext = false;

  @override
  Future<ChatDefaults> load() async => current;

  @override
  Future<void> save(ChatDefaults defaults) async {
    writes.add(defaults);
    final gate = nextSave;
    nextSave = null;
    if (gate != null) await gate.future;
    if (failNext) {
      failNext = false;
      throw StateError('测试存储失败');
    }
    current = defaults;
  }
}

Finder _field(int index) => find.byType(TextBox).at(index);

Future<(ChatDefaultsRepository, _ControlledStorage)> _pump(
  WidgetTester tester, [
  ChatDefaults initial = ChatDefaults.recommended,
]) async {
  await tester.binding.setSurfaceSize(const Size(1280, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final storage = _ControlledStorage(initial);
  final repository = ChatDefaultsRepository(storage: storage);
  await repository.load();
  addTearDown(repository.dispose);
  await tester.pumpWidget(
    FluentApp(
      theme: buildFluentLightTheme(),
      home: SettingsChatDefaultsPage(repository: repository),
    ),
  );
  await tester.pumpAndSettle();
  return (repository, storage);
}

Future<void> _enableBudget(WidgetTester tester) async {
  await tester.tap(find.text('启用字符预算'));
  await tester.pumpAndSettle();
}

Future<void> _tapAction(WidgetTester tester, String label) async {
  // 先提交输入触发的重建，再推进 InfoBar 的延迟入场动画。
  await tester.pump();
  await tester.tap(find.text(label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

Future<void> _finish(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void _expectLocked(WidgetTester tester) {
  expect(
    tester
        .widgetList<TextBox>(find.byType(TextBox))
        .every((box) => !box.enabled),
    isTrue,
  );
  expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
  for (final toggle in tester.widgetList<ToggleSwitch>(
    find.byType(ToggleSwitch),
  )) {
    expect(toggle.onChanged, isNull);
  }
  expect(
    tester.widget<Button>(find.widgetWithText(Button, '取消').first).onPressed,
    isNull,
  );
  expect(
    tester.widget<Button>(find.widgetWithText(Button, '恢复推荐值')).onPressed,
    isNull,
  );
}

void main() {
  for (final entry in [
    (1, '0～200000', ['abc', '', '   ', '1.5', '0x10', '-1', '200001']),
    (2, '1～600', ['abc', '', '   ', '1.5', '0', '601']),
    (3, '1～200', ['abc', '', '   ', '1.5', '0', '201']),
    (4, '1～500000', ['abc', '', '   ', '1.5', '0', '500001']),
  ]) {
    testWidgets('字段 ${entry.$1} 拒绝非法格式及越界，保留草稿且不写入', (tester) async {
      final (repository, storage) = await _pump(tester);
      if (entry.$1 == 4) await _enableBudget(tester);
      for (final input in entry.$3) {
        await tester.enterText(_field(entry.$1), input);
        await _tapAction(tester, '保存');
        expect(find.text('请输入 ${entry.$2} 的整数'), findsOneWidget);
        expect(
          tester.widget<TextBox>(_field(entry.$1)).controller!.text,
          input,
        );
        expect(storage.writes, isEmpty);
        expect(repository.defaults, ChatDefaults.recommended);
        expect(find.text('已保存对话默认'), findsNothing);
      }
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('请输入 ${entry.$2} 的整数'), findsNothing);
      expect(storage.writes, isEmpty);
    });
  }

  for (final upper in [false, true]) {
    testWidgets('所有数值字段允许${upper ? '上' : '下'}边界', (tester) async {
      final (repository, storage) = await _pump(tester);
      await _enableBudget(tester);
      final values = upper
          ? ['200000', '600', '200', '500000']
          : ['0', '1', '1', '1'];
      for (var i = 0; i < values.length; i++) {
        await tester.enterText(_field(i + 1), values[i]);
      }
      await _tapAction(tester, '保存');
      expect(storage.writes, hasLength(1));
      final saved = repository.defaults;
      expect(saved.maxTokens, int.parse(values[0]));
      expect(saved.apiTimeoutMs, int.parse(values[1]) * 1000);
      expect(saved.contextMaxTurns, int.parse(values[2]));
      expect(saved.contextMaxChars, int.parse(values[3]));
      expect(find.text('已保存对话默认'), findsOneWidget);
      await _finish(tester);
    });
  }

  testWidgets('关闭裁剪项忽略非法草稿并保留已保存数值', (tester) async {
    const initial = ChatDefaults(contextMaxTurns: 37, contextMaxChars: 45678);
    final (repository, storage) = await _pump(tester, initial);
    await _enableBudget(tester);
    await tester.enterText(_field(3), '非法轮数');
    await tester.enterText(_field(4), '');
    await _tapAction(tester, '保存');
    expect(find.text('请输入 1～200 的整数'), findsOneWidget);
    expect(find.text('请输入 1～500000 的整数'), findsOneWidget);
    await tester.tap(find.text('按轮数裁剪上下文'));
    await tester.tap(find.text('启用字符预算'));
    await tester.enterText(_field(0), '其他参数仍可保存');
    await _tapAction(tester, '保存');
    expect(storage.writes, hasLength(1));
    expect(repository.defaults.systemPrompt, '其他参数仍可保存');
    expect(repository.defaults.contextTrimEnabled, isFalse);
    expect(repository.defaults.contextMaxCharsEnabled, isFalse);
    expect(repository.defaults.contextMaxTurns, 37);
    expect(repository.defaults.contextMaxChars, 45678);
    expect(tester.widget<TextBox>(_field(3)).controller!.text, '37');
    expect(tester.widget<TextBox>(_field(4)).controller!.text, '45678');
    expect(find.text('请输入 1～200 的整数'), findsNothing);
    expect(find.text('请输入 1～500000 的整数'), findsNothing);
    await _finish(tester);
  });

  testWidgets('保存等待期间锁定表单及旧事件，仍可滚动，完成后解锁', (tester) async {
    final (repository, storage) = await _pump(tester);
    await _enableBudget(tester);
    await tester.enterText(_field(0), '待保存草稿');
    final slider = tester.widget<Slider>(find.byType(Slider));
    final toggles = tester
        .widgetList<ToggleSwitch>(find.byType(ToggleSwitch))
        .toList();
    final cancel = tester
        .widget<Button>(find.widgetWithText(Button, '取消'))
        .onPressed!;
    final reset = tester
        .widget<Button>(find.widgetWithText(Button, '恢复推荐值'))
        .onPressed!;
    final gate = Completer<void>();
    storage.nextSave = gate;
    await _tapAction(tester, '保存');
    _expectLocked(tester);
    slider.onChanged!(1.9);
    for (final toggle in toggles) {
      toggle.onChanged!(!toggle.checked);
    }
    cancel();
    reset();
    await tester.pump();
    expect(storage.writes, hasLength(1));
    expect(find.text('恢复推荐值？'), findsNothing);
    expect(tester.widget<Slider>(find.byType(Slider)).value, slider.value);
    expect(tester.widget<TextBox>(_field(0)).controller!.text, '待保存草稿');
    await tester.binding.setSurfaceSize(const Size(1280, 600));
    await tester.pump();
    final scroll = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
    expect(scroll.pixels, greaterThan(0));
    gate.complete();
    await tester.pumpAndSettle();
    expect(repository.defaults.systemPrompt, '待保存草稿');
    await tester.binding.setSurfaceSize(const Size(1280, 1400));
    await tester.pumpAndSettle();
    expect(tester.widget<TextBox>(_field(0)).enabled, isTrue);
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);
    await _finish(tester);
  });

  testWidgets('保存失败保留草稿与原运行配置，可直接重试或取消', (tester) async {
    const initial = ChatDefaults(systemPrompt: '已保存提示');
    final (repository, storage) = await _pump(tester, initial);
    storage.failNext = true;
    await tester.enterText(_field(0), '重试草稿');
    await _tapAction(tester, '保存');
    expect(repository.defaults, initial);
    expect(tester.widget<TextBox>(_field(0)).controller!.text, '重试草稿');
    expect(tester.widget<TextBox>(_field(0)).enabled, isTrue);
    expect(find.textContaining('保存失败：'), findsOneWidget);
    expect(find.text('已保存对话默认'), findsNothing);
    await _tapAction(tester, '保存');
    expect(find.text('覆盖最新配置？'), findsNothing);
    expect(repository.defaults.systemPrompt, '重试草稿');
    expect(storage.writes, hasLength(2));
    storage.failNext = true;
    await tester.enterText(_field(0), '放弃的草稿');
    await _tapAction(tester, '保存');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextBox>(_field(0)).controller!.text, '重试草稿');
    expect(repository.defaults.systemPrompt, '重试草稿');
    await _finish(tester);
  });

  testWidgets('恢复推荐值绕过非法草稿，确认及存储期间均锁定表单', (tester) async {
    final (repository, storage) = await _pump(
      tester,
      const ChatDefaults(systemPrompt: '旧提示', maxTokens: 1234),
    );
    await tester.enterText(_field(1), '非法');
    await _tapAction(tester, '保存');
    final reset = tester
        .widget<Button>(find.widgetWithText(Button, '恢复推荐值'))
        .onPressed!;
    reset();
    await tester.pumpAndSettle();
    _expectLocked(tester);
    reset();
    await tester.pumpAndSettle();
    expect(find.text('恢复推荐值？'), findsOneWidget);
    final gate = Completer<void>();
    storage.nextSave = gate;
    await _tapAction(tester, '恢复');
    _expectLocked(tester);
    expect(storage.writes, hasLength(1));
    gate.complete();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(repository.defaults, ChatDefaults.recommended);
    expect(tester.widget<TextBox>(_field(1)).controller!.text, '0');
    expect(find.text('请输入 0～200000 的整数'), findsNothing);
    expect(find.text('已恢复推荐值'), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('取消恢复保留非法草稿，恢复失败后可重试或取消草稿', (tester) async {
    const initial = ChatDefaults(systemPrompt: '原提示');
    final (repository, storage) = await _pump(tester, initial);
    await tester.enterText(_field(1), '非法');
    await tester.tap(find.text('恢复推荐值'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    expect(storage.writes, isEmpty);
    expect(tester.widget<TextBox>(_field(1)).controller!.text, '非法');
    expect(tester.widget<TextBox>(_field(1)).enabled, isTrue);
    storage.failNext = true;
    await tester.tap(find.text('恢复推荐值'));
    await tester.pumpAndSettle();
    await _tapAction(tester, '恢复');
    expect(repository.defaults, initial);
    expect(tester.widget<TextBox>(_field(1)).controller!.text, '非法');
    expect(find.textContaining('恢复失败：'), findsOneWidget);
    expect(find.text('已恢复推荐值'), findsNothing);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextBox>(_field(1)).controller!.text, '0');
    await tester.tap(find.text('恢复推荐值'));
    await tester.pumpAndSettle();
    await _tapAction(tester, '恢复');
    expect(repository.defaults, ChatDefaults.recommended);
    expect(storage.writes, hasLength(2));
    await _finish(tester);
  });

  testWidgets('冲突确认拒绝后可编辑，再确认仅覆盖允许的字段', (tester) async {
    final (repository, storage) = await _pump(tester);
    await tester.enterText(_field(0), '本机草稿');
    await tester.tap(find.text('按轮数裁剪上下文'));
    await repository.save(
      const ChatDefaults(systemPrompt: '导入提示', contextMaxTurns: 83),
    );
    await tester.pumpAndSettle();
    await _tapAction(tester, '保存');
    _expectLocked(tester);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextBox>(_field(0)).enabled, isTrue);
    expect(tester.widget<TextBox>(_field(0)).controller!.text, '本机草稿');
    expect(storage.writes, hasLength(1));
    await _tapAction(tester, '保存');
    await _tapAction(tester, '覆盖保存');
    expect(repository.defaults.systemPrompt, '本机草稿');
    expect(repository.defaults.contextTrimEnabled, isFalse);
    expect(repository.defaults.contextMaxTurns, 83);
    await _finish(tester);
  });

  testWidgets('恢复确认等待期间页面被移除时不会写入或 setState', (tester) async {
    final (_, storage) = await _pump(tester);
    await tester.tap(find.text('恢复推荐值'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      FluentApp(theme: buildFluentLightTheme(), home: const SizedBox.shrink()),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SettingsChatDefaultsPage), findsNothing);
    expect(find.text('恢复推荐值？'), findsOneWidget);
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    expect(storage.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
