import 'dart:convert';

import 'package:core/core.dart';
// ignore: depend_on_referenced_packages
import 'package:file_selector_ios/file_selector_ios.dart';
// ignore: depend_on_referenced_packages, implementation_imports
import 'package:file_selector_ios/src/messages.g.dart';
// ignore: depend_on_referenced_packages
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_material/pages/settings/settings_about_tab.dart';
import 'package:package_info_plus/package_info_plus.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';

class _IosPickerApi extends FileSelectorApi {
  int calls = 0;
  FileSelectorConfig? config;
  List<String> paths = [];
  Object? error;

  @override
  Future<List<String>> openFile(FileSelectorConfig config) async {
    calls++;
    this.config = config;
    if (error != null) throw error!;
    return paths;
  }
}

class _MemoryReadIosPicker extends FileSelectorIOS {
  _MemoryReadIosPicker(FileSelectorApi superApi, this.raw) : super(api: superApi);
  final String raw;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    final selected = await super.openFile(
      acceptedTypeGroups: acceptedTypeGroups,
      initialDirectory: initialDirectory,
      confirmButtonText: confirmButtonText,
    );
    return selected == null
        ? null
        : XFile.fromData(utf8.encode(raw), name: 'backup.json');
  }
}

void main() {
  for (final scenario in [
    'preview',
    'cancel',
    'missing',
    'platform',
    'argument',
  ]) {
    testWidgets('real iOS picker entry: $scenario', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(1280, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final previous = FileSelectorPlatform.instance;
      final api = _IosPickerApi();
      addTearDown(() => FileSelectorPlatform.instance = previous);
      final providers = ProviderRepository(storage: MemoryProviderStorage());
      final appearance = AppearanceRepository(
        storage: MemoryAppearanceStorage(),
      );
      final defaults = ChatDefaultsRepository(
        storage: MemoryChatDefaultsStorage(),
      );
      final chats = ChatSessionRepository(storage: MemoryChatSessionStorage());
      final images = ImageSessionRepository(
        storage: MemoryImageSessionStorage(),
      );
      final videos = VideoSessionRepository(
        storage: MemoryVideoSessionStorage(),
      );
      await Future.wait([
        providers.load(),
        appearance.load(),
        defaults.load(),
        chats.load(),
        images.load(),
        videos.load(),
      ]);
      final backup = DataBackupService(
        providers: providers,
        appearance: appearance,
        chatDefaults: defaults,
        chatSessions: chats,
        imageSessions: images,
        videoSessions: videos,
      );
      FileSelectorPlatform.instance = _MemoryReadIosPicker(
        api,
        await backup.exportBackupJson(),
      );
      if (scenario == 'preview') api.paths = ['/fixture/backup.json'];
      if (scenario == 'missing') {
        api.error = MissingPluginException('PRIVATE_SENTINEL');
      }
      if (scenario == 'platform') {
        api.error = PlatformException(
          code: 'PRIVATE_SENTINEL',
          message: 'PRIVATE_SENTINEL',
        );
      }
      if (scenario == 'argument') api.error = ArgumentError('PRIVATE_SENTINEL');
      final before = jsonEncode(
        providers.providers.map((p) => p.toJson()).toList(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsAboutTab(
              dataBackupService: backup,
              packageInfo: PackageInfo(
                appName: 'test',
                packageName: 'test',
                version: '1',
                buildNumber: '1',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('导入 / 导出'));
      await tester.tap(find.text('导入 / 导出'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('导入设置'));
      await tester.pumpAndSettle();
      expect(api.calls, 1);
      expect(api.config!.utis, ['public.json']);
      expect(find.textContaining('PRIVATE_SENTINEL'), findsNothing);
      if (scenario == 'preview') {
        await tester.tap(find.text('导入').last);
        await tester.pumpAndSettle();
        expect(find.text('导入预览'), findsOneWidget);
        await tester.tap(find.text('取消').last);
      } else if (scenario == 'cancel') {
        expect(find.textContaining('文件选择器'), findsNothing);
      } else {
        expect(
          find.textContaining(switch (scenario) {
            'missing' => '文件选择器组件不可用',
            'platform' => '系统文件选择器打开失败',
            _ => '文件选择器类型配置不兼容',
          }),
          findsOneWidget,
        );
      }
      expect(
        jsonEncode(providers.providers.map((p) => p.toJson()).toList()),
        before,
      );
      expect(
        (await SharedPreferences.getInstance()).getString(
          'core.backup_import_progress.v1',
        ),
        isNull,
      );
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpWidget(const SizedBox.shrink());
      await providers.waitForPersist();
      for (final repo in [
        providers,
        appearance,
        defaults,
        chats,
        images,
        videos,
      ]) {
        repo.dispose();
      }
    });
  }
}
