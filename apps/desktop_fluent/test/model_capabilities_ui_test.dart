import 'package:core/core.dart';
import 'package:desktop_fluent/pages/settings/settings_providers_page.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final save in [true, false]) {
    testWidgets('dirty model switch keeps capability drafts (save=$save)', (
      tester,
    ) async {
      await _modelSwitch(tester, save: save);
    });
  }
  testWidgets(
    'capability draft changes require save and preserve per-model values',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1500, 2400));
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
        FluentApp(
          theme: buildFluentLightTheme(),
          home: SettingsProvidersPage(repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('当前模型能力：unknown'), findsOneWidget);
      final picker = find.byType(ComboBox<int>).first;
      await tester.ensureVisible(picker);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('支持').last);
      await tester.pumpAndSettle();
      expect(repo.providers.single.modelCapabilityOverrides, isEmpty);
      await tester.ensureVisible(find.text('保存'));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(
        repo.providers.single.modelCapabilityOverrides['unknown']?.vision,
        isTrue,
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await repo.waitForPersist();
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );
}

Future<void> _modelSwitch(WidgetTester tester, {required bool save}) async {
  await tester.binding.setSurfaceSize(const Size(1500, 4000));
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
    FluentApp(
      theme: buildFluentLightTheme(),
      home: SettingsProvidersPage(repository: repo),
    ),
  );

  await tester.pumpAndSettle();
  Finder input(String text) => find.byWidgetPredicate(
    (widget) => widget is EditableText && widget.controller.text == text,
  );
  await tester.ensureVisible(input('Fixture'));
  await tester.enterText(input('Fixture'), 'Dirty fixture');
  await tester.pumpAndSettle();
  await tester.ensureVisible(input('model-a'));
  await tester.enterText(input('model-a'), '  model-b  ');
  await tester.pumpAndSettle();
  Future<void> choose(int field, String label) async {
    final picker = find.byType(ComboBox<int>).at(field);
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
    await tester.ensureVisible(input('model-b'));
    await tester.enterText(input('model-b'), '   ');
    await tester.pumpAndSettle();
    expect(find.text('当前模型能力：请先填写对话模型'), findsOneWidget);
    for (final picker in tester.widgetList<ComboBox<int>>(
      find.byType(ComboBox<int>),
    )) {
      expect(picker.onChanged, isNull);
    }
    await tester.enterText(input('   '), 'model-a');
    await tester.pumpAndSettle();
    expect(find.text('当前模型能力：model-a'), findsOneWidget);
    expect(
      tester.widget<ComboBox<int>>(find.byType(ComboBox<int>).first).value,
      2,
    );
    await tester.enterText(input('model-a'), 'model-b');
    await tester.pumpAndSettle();
    expect(
      tester.widget<ComboBox<int>>(find.byType(ComboBox<int>).first).value,
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
