import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_material/widgets/filterable_model_picker.dart';

const _options = [
  ModelSelectOption(value: 'model-a', label: 'Alpha'),
  ModelSelectOption(value: 'model-b', label: 'Beta'),
];

Future<void> _mount(
  WidgetTester tester,
  TextEditingController controller,
  List<String> changes, {
  bool allowClear = false,
  List<ModelSelectOption> options = _options,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildMaterialLightTheme(),
      home: Scaffold(
        body: FilterableModelPicker(
          controller: controller,
          options: options,
          placeholder: '选择模型',
          onChanged: changes.add,
          allowClear: allowClear,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('箭头不唤起键盘，已有模型不限制展开列表', (tester) async {
    final controller = TextEditingController(text: 'model-a');
    addTearDown(controller.dispose);
    final changes = <String>[];
    await _mount(tester, controller, changes);

    await tester.tap(find.byTooltip('展开模型列表'));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(changes, isEmpty);

    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();
    expect(controller.text, 'model-b');
    expect(changes, ['model-b']);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('搜索不覆盖已选值，失焦和输入法完成不提交或关闭列表', (tester) async {
    final controller = TextEditingController(text: 'model-a');
    addTearDown(controller.dispose);
    final changes = <String>[];
    await _mount(tester, controller, changes);

    await tester.enterText(find.byType(TextField), 'Bet');
    await tester.pumpAndSettle();
    expect(controller.text, 'model-a');
    expect(changes, isEmpty);
    expect(find.byType(InputChip), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Alpha'), findsNothing);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Beta'), findsOneWidget);
    expect(controller.text, 'model-a');
    expect(changes, isEmpty);

    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();
    expect(controller.text, 'model-b');
    expect(changes, ['model-b']);
  });

  testWidgets('无匹配的输入不能成为模型，外部更新清理搜索', (tester) async {
    final controller = TextEditingController(text: 'model-a');
    addTearDown(controller.dispose);
    final changes = <String>[];
    await _mount(tester, controller, changes);
    await tester.enterText(find.byType(TextField), 'unknown');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('无匹配「unknown」'), findsOneWidget);
    expect(controller.text, 'model-a');
    expect(changes, isEmpty);

    controller.text = 'model-b';
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'model-b'), findsOneWidget);
  });

  testWidgets('滚动列表收起键盘后仍可点选', (tester) async {
    final controller = TextEditingController(text: 'model-a');
    addTearDown(controller.dispose);
    final changes = <String>[];
    await _mount(
      tester,
      controller,
      changes,
      options: [
        for (var i = 0; i < 20; i++)
          ModelSelectOption(value: 'model-$i', label: 'Model $i'),
      ],
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -160));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.byType(ListView), findsOneWidget);
    expect(controller.text, 'model-a');
    expect(changes, isEmpty);
    final tile = find.byType(ListTile).hitTestable().first;
    final label = tester
        .widget<Text>(
          find.descendant(of: tile, matching: find.byType(Text)).first,
        )
        .data!;
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(controller.text, 'model-${label.split(' ').last}');
    expect(changes, [controller.text]);
  });

  testWidgets('视频可显式选择不使用，搜索本身不清除已选模型', (tester) async {
    final controller = TextEditingController(text: 'model-a');
    addTearDown(controller.dispose);
    final changes = <String>[];
    await _mount(tester, controller, changes, allowClear: true);
    await tester.enterText(find.byType(TextField), 'Alpha');
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(controller.text, 'model-a');
    expect(changes, isEmpty);
    await tester.tap(find.text('不使用'));
    await tester.pumpAndSettle();
    expect(controller.text, '');
    expect(changes, ['']);
    expect(find.byType(InputChip), findsNothing);
  });
}
