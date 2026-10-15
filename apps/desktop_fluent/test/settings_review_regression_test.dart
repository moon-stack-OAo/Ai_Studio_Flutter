import 'package:core/core.dart';
import 'package:desktop_fluent/pages/settings/settings_about_page.dart';
import 'package:desktop_fluent/pages/settings/settings_chat_defaults_page.dart';
import 'package:desktop_fluent/pages/settings/settings_mcp_page.dart';
import 'package:desktop_fluent/pages/settings/settings_providers_page.dart';
import 'package:desktop_fluent/pages/settings/settings_skills_page.dart';
import 'package:desktop_fluent/pages/settings/widgets/backup_import_dialog.dart';
import 'package:desktop_fluent/update/update_controller.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

const _skill = CustomSkill(
  id: 'review-skill',
  name: '测试技能',
  prompt: '本机内容',
  targets: {SkillTarget.chat},
);

class _Fixture {
  final providers = ProviderRepository(storage: MemoryProviderStorage());
  final skills = SkillRepository(storage: MemorySkillStorage([_skill]));
  final appearance = AppearanceRepository(storage: MemoryAppearanceStorage());
  final defaults = ChatDefaultsRepository(storage: MemoryChatDefaultsStorage());
  final chats = ChatSessionRepository(storage: MemoryChatSessionStorage());
  final images = ImageSessionRepository(storage: MemoryImageSessionStorage());
  final videos = VideoSessionRepository(storage: MemoryVideoSessionStorage());
  late final backup = DataBackupService(
    providers: providers,
    appearance: appearance,
    chatDefaults: defaults,
    chatSessions: chats,
    imageSessions: images,
    videoSessions: videos,
    skillRepository: skills,
  );

  Future<void> load() => Future.wait([
    providers.load(),
    skills.load(),
    appearance.load(),
    defaults.load(),
    chats.load(),
    images.load(),
    videos.load(),
  ]);

  void dispose() {
    for (final repository in [
      providers,
      skills,
      appearance,
      defaults,
      chats,
      images,
      videos,
    ]) {
      repository.dispose();
    }
  }
}

class _StatusUpdater extends UpdateController {
  _StatusUpdater() : super(client: UpdateClient(), currentVersion: '1.0.0');
  UpdateCheckResult? result;
  bool checking = false;
  bool configured = true;
  bool cachedUpdate = false;

  @override
  UpdateCheckResult? get lastCheck => result;
  @override
  bool get isChecking => checking;
  @override
  bool get isConfigured => configured;
  @override
  bool get hasAvailableUpdate => cachedUpdate;
  @override
  Future<void> ensureCurrentVersion() async {}

  void refresh() => notifyListeners();
}

Future<void> _pump(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(
    FluentApp(theme: buildFluentLightTheme(), home: page),
  );
  await tester.pumpAndSettle();
}

TextBox _keyBox(WidgetTester tester) => tester
    .widgetList<TextBox>(find.byType(TextBox))
    .singleWhere((box) => box.obscureText);

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'AI Studio',
      packageName: 'studio.test',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  Future<_Fixture> fixture(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final value = _Fixture();
    await value.load();
    addTearDown(value.dispose);
    return value;
  }

  testWidgets('同 ID 提供商导入及清除密钥后，干净表单读取最新配置', (tester) async {
    final f = await fixture(tester);
    final provider = f.providers.activeProvider!;
    await f.providers.saveProvider(provider.copyWith(apiKey: 'old-test-key'));
    await _pump(tester, SettingsProvidersPage(repository: f.providers));
    await f.providers.saveProvider(
      provider.copyWith(apiKey: 'imported-test-key'),
    );
    await tester.pumpAndSettle();
    expect(_keyBox(tester).controller!.text, 'imported-test-key');
    await f.backup.clearLocalData(const ClearLocalDataFlags(secrets: true));
    await tester.pumpAndSettle();
    expect(_keyBox(tester).controller!.text, isEmpty);
  });

  testWidgets('提供商草稿保留，取消覆盖不会改写导入配置', (tester) async {
    final f = await fixture(tester);
    final provider = f.providers.activeProvider!;
    await f.providers.saveProvider(provider.copyWith(apiKey: 'old-test-key'));
    await _pump(tester, SettingsProvidersPage(repository: f.providers));
    final field = find.byWidgetPredicate((w) => w is TextBox && w.obscureText);
    await tester.enterText(field, 'draft-test-key');
    await f.providers.saveProvider(
      provider.copyWith(apiKey: 'imported-test-key'),
    );
    await tester.pumpAndSettle();
    expect(_keyBox(tester).controller!.text, 'draft-test-key');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('覆盖最新配置？'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(f.providers.activeProvider!.apiKey, 'imported-test-key');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(_keyBox(tester).controller!.text, 'imported-test-key');
  });

  testWidgets('清空技能后关闭保活编辑器，不能重新保存已删技能', (tester) async {
    final f = await fixture(tester);
    await _pump(tester, SettingsSkillsPage(repository: f.skills));
    await tester.tap(find.text(_skill.name));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('skill_name')), '未保存草稿');
    await f.skills.clear();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('skill_name')), findsNothing);
    expect(find.text('保存技能'), findsNothing);
    expect(f.skills.skills, isEmpty);
  });

  testWidgets('技能同 ID 导入刷新干净编辑器，冲突草稿需确认覆盖', (tester) async {
    final f = await fixture(tester);
    await _pump(tester, SettingsSkillsPage(repository: f.skills));
    await tester.tap(find.text(_skill.name));
    await tester.pumpAndSettle();
    final name = find.byKey(const ValueKey('skill_name'));
    await f.skills.saveSkill(_skill.copyWith(name: '导入名称'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextBox>(name).controller!.text, '导入名称');
    await tester.enterText(name, '保留草稿');
    await f.skills.saveSkill(_skill.copyWith(name: '再次导入'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextBox>(name).controller!.text, '保留草稿');
    await tester.tap(find.text('保存技能'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(f.skills.skills.single.name, '再次导入');
    await tester.tap(find.text('保存技能'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('覆盖保存'));
    await tester.pumpAndSettle();
    expect(f.skills.skills.single.name, '保留草稿');
  });

  testWidgets('对话默认草稿与导入冲突时需确认，取消后载入最新配置', (tester) async {
    final f = await fixture(tester);
    await _pump(tester, SettingsChatDefaultsPage(repository: f.defaults));
    final system = find.byType(TextBox).first;
    await tester.enterText(system, '本机草稿');
    await f.defaults.save(const ChatDefaults(systemPrompt: '导入提示'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('覆盖最新配置？'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(f.defaults.defaults.systemPrompt, '导入提示');
    expect(tester.widget<TextBox>(system).controller!.text, '本机草稿');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextBox>(system).controller!.text, '导入提示');
  });

  testWidgets('MCP 同 ID 导入刷新干净表单，有草稿时阻止静默覆盖', (tester) async {
    await fixture(tester);
    final repository = McpServerRepository(
      storage: MemoryMcpServerStorage(),
      secretStore: MemorySecretStore(),
    );
    await repository.load();
    final id = await repository.add(
      displayName: '测试 MCP',
      baseUrl: 'https://old.example.com/mcp',
    );
    addTearDown(repository.dispose);
    await _pump(
      tester,
      SettingsMcpPage(
        repository: repository,
        sessionFactory: HttpSseMcpSessionFactory(
          secretStoreAuthBuilder: (_) => NoneMcpAuth(),
        ),
      ),
    );
    final name = find.byType(TextBox).first;
    await repository.update(
      repository.findById(id)!.copyWith(displayName: '导入 MCP'),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<TextBox>(name).controller!.text, '导入 MCP');
    await tester.enterText(name, 'MCP 草稿');
    await repository.update(
      repository.findById(id)!.copyWith(displayName: '再次导入 MCP'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('覆盖最新配置？'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(repository.findById(id)!.displayName, '再次导入 MCP');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('取消技能导入选项后保留本机技能，其他设置仍导入', (tester) async {
    final f = await fixture(tester);
    await f.defaults.save(const ChatDefaults(systemPrompt: '备份提示'));
    await f.skills.saveSkill(_skill.copyWith(name: '备份技能'));
    final raw = await f.backup.exportBackupJson();
    await f.defaults.save(const ChatDefaults(systemPrompt: '本机提示'));
    await f.skills.saveSkill(_skill);
    DataBackupImportOptions? options;
    await _pump(
      tester,
      Builder(
        builder: (context) => Button(
          onPressed: () async {
            options = await showDialog<DataBackupImportOptions>(
              context: context,
              builder: (_) =>
                  BackupImportDialog(payload: DataBackupPayload.parse(raw)),
            );
          },
          child: const Text('打开导入'),
        ),
      ),
    );
    await tester.tap(find.text('打开导入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('合并自定义技能（1 项）'));
    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();
    expect(options!.importSkills, isFalse);
    await f.backup.importBackup(raw, options: options!);
    expect(f.skills.skills.single.name, _skill.name);
    expect(f.defaults.defaults.systemPrompt, '备份提示');
  });

  testWidgets('更新徽标区分每个检查状态，失败不会被缓存更新掩盖', (tester) async {
    final f = await fixture(tester);
    final updater = _StatusUpdater();
    addTearDown(updater.dispose);
    await _pump(
      tester,
      SettingsAboutPage(
        appearanceRepository: f.appearance,
        dataBackupService: f.backup,
        updateController: updater,
      ),
    );
    expect(find.text('尚未检查'), findsOneWidget);
    updater.checking = true;
    updater.refresh();
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('update_status')),
        matching: find.text('检查中…'),
      ),
      findsOneWidget,
    );
    updater.checking = false;
    updater.cachedUpdate = true;
    for (final entry in {
      UpdateCheckStatus.failed: '检查失败',
      UpdateCheckStatus.notConfigured: '未配置更新源',
      UpdateCheckStatus.noPlatformAsset: '无平台安装包',
      UpdateCheckStatus.upToDate: '已是最新',
      UpdateCheckStatus.available: '有更新',
    }.entries) {
      updater.result = UpdateCheckResult(
        status: entry.key,
        currentVersion: '1.0.0',
      );
      updater.refresh();
      await tester.pump();
      expect(find.text(entry.value), findsOneWidget);
      if (entry.key != UpdateCheckStatus.upToDate) {
        expect(find.text('已是最新'), findsNothing);
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
