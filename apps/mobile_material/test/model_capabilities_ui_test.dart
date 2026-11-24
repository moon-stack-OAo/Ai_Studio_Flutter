import 'package:core/core.dart';
import 'package:mobile_material/pages/settings/provider_edit_sheet.dart';
import 'package:mobile_material/widgets/filterable_model_picker.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final save in [true, false]) {
    testWidgets('dirty model switch keeps capability drafts (save=$save)', (
      tester,
    ) async {
      await _modelSwitch(tester, save: save);
    });
  }
  testWidgets('capability draft changes require save', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = ProviderRepository(
      storage: MemoryProviderStorage(
        ProviderStoreSnapshot(
          providers: [
            ProviderConfig(
              id: 'p',
              name: 'Fixture',
              type: ProviderType.openaiCompatible,
              baseUrl: 'https://example.com/v1',
              chatModel: 'unknown',
            ),
          ],
          activeProviderId: 'p',
        ),
      ),
    );
    await repo.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildMaterialLightTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showProviderEditSheet(
                context: context,
                repository: repo,
                providerId: 'p',
              ),
              child: const Text('edit'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('edit'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('当前模型能力：unknown'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('当前模型能力：unknown'), findsOneWidget);
    final picker = find.byType(DropdownButton<int>).first;
    await tester.ensureVisible(picker);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('支持').last);
    await tester.pumpAndSettle();
    expect(repo.providers.single.modelCapabilityOverrides, isEmpty);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(
      repo.providers.single.modelCapabilityOverrides['unknown']?.vision,
      isTrue,
    );
    await repo.waitForPersist();
    await tester.pumpWidget(const SizedBox());
    repo.dispose();
  });
}

Future<void> _modelSwitch(WidgetTester tester, {required bool save}) async {
  await tester.binding.setSurfaceSize(const Size(800, 4000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final storage = MemoryProviderStorage(
    ProviderStoreSnapshot(
      providers: [
        ProviderConfig(
          id: 'p',
          name: 'Fixture',
          type: ProviderType.openaiCompatible,
          baseUrl: 'https://example.com/v1',
          chatModel: 'model-a',
          modelCapabilityOverrides: const {
            'model-a': ModelCapabilityOverride(vision: false, tools: true),
            'model-b': ModelCapabilityOverride(vision: false, tools: false),
          },
        ),
      ],
      activeProviderId: 'p',
    ),
  );
  final repo = ProviderRepository(storage: storage);
  await repo.load();
  await tester.pumpWidget(
    MaterialApp(
      theme: buildMaterialLightTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showProviderEditSheet(
              context: context,
              repository: repo,
              providerId: 'p',
            ),
            child: const Text('edit'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('edit'));
  await tester.pumpAndSettle();
  Finder input(String text) => find.byWidgetPredicate(
    (widget) => widget is EditableText && widget.controller.text == text,
  );
  await tester.ensureVisible(input('Fixture'));
  await tester.enterText(input('Fixture'), 'Dirty fixture');
  await tester.pumpAndSettle();
  final modelPicker = find.byType(FilterableModelPicker).first;
  await tester.scrollUntilVisible(
    modelPicker,
    300,
    scrollable: find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  final modelController = tester
      .widget<FilterableModelPicker>(modelPicker)
      .controller;
  // Material uses a separate search field; simulate the committed picker value.
  void setModel(String id) {
    modelController.text = id;
    tester.widget<FilterableModelPicker>(modelPicker).onChanged(id);
  }

  await tester.scrollUntilVisible(
    find.text('当前模型能力：model-a'),
    200,
    scrollable: find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
  setModel('  model-b  ');
  await tester.pumpAndSettle();
  Future<void> choose(int field, String label) async {
    final picker = find.byType(DropdownButton<int>).at(field);
    await tester.ensureVisible(picker);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  await choose(0, '支持');
  await choose(1, '支持');
  expect(
    repo.providers.single.modelCapabilityOverrides['model-a']?.vision,
    isFalse,
  );
  expect(
    repo.providers.single.modelCapabilityOverrides['model-b']?.vision,
    isFalse,
  );
  if (save) {
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final saved = repo.providers.single;
    expect(saved.chatModel, 'model-b');
    expect(saved.modelCapabilityOverrides['model-a']?.vision, isFalse);
    expect(saved.modelCapabilityOverrides['model-a']?.tools, isTrue);
    expect(saved.modelCapabilityOverrides['model-b']?.vision, isTrue);
    expect(saved.modelCapabilityOverrides['model-b']?.tools, isTrue);
    expect(
      saved.modelCapabilityOverrides.keys,
      unorderedEquals(['model-a', 'model-b']),
    );
  } else {
    // Empty/whitespace model disables editing without deleting either draft.
    setModel('   ');
    await tester.pumpAndSettle();
    expect(find.text('当前模型能力：请先填写对话模型'), findsOneWidget);
    for (final picker in tester.widgetList<DropdownButton<int>>(
      find.byType(DropdownButton<int>),
    )) {
      expect(picker.onChanged, isNull);
    }
    setModel('model-a');
    await tester.pumpAndSettle();
    expect(find.text('当前模型能力：model-a'), findsOneWidget);
    expect(
      tester
          .widget<DropdownButton<int>>(find.byType(DropdownButton<int>).first)
          .value,
      2,
    );
    setModel('model-b');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownButton<int>>(find.byType(DropdownButton<int>).first)
          .value,
      1,
    );
    await tester.ensureVisible(find.text('取消'));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(repo.providers.single.chatModel, 'model-a');
    expect(
      repo.providers.single.modelCapabilityOverrides['model-b']?.vision,
      isFalse,
    );
    expect(
      repo.providers.single.modelCapabilityOverrides['model-b']?.tools,
      isFalse,
    );
  }
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
  await repo.waitForPersist();
  await tester.pumpWidget(const SizedBox());
  repo.dispose();
}
