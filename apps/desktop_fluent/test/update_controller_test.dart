import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:desktop_fluent/update/update_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UpdateController 完整性校验', () {
    late Directory dir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      dir = await Directory.systemTemp.createTemp('ai_studio_upd_ctrl_');
    });

    tearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    test('缺少完整性信息：检查失败且不进入可安装态', () async {
      final payload = utf8.encode('fake-installer-bytes');
      final mock = MockClient((request) async {
        if (request.url.path.endsWith('.json')) {
          return http.Response(
            jsonEncode({
              'version': '9.9.9',
              'notes': 'test',
              'pub_date': '2026-09-08T00:00:00.000Z',
              'platforms': {
                'windows-x86_64': {
                  'url': 'https://example.com/setup.exe',
                  'signature': '',
                },
              },
            }),
            200,
          );
        }
        return http.Response.bytes(
          payload,
          200,
          headers: {'content-length': '${payload.length}'},
        );
      });

      final client = UpdateClient(
        client: mock,
        manifestUrl: 'https://example.com/latest.json',
        downloadDirectory: dir,
        minisignPubkey: base64Encode(utf8.encode('dummy-pubkey')),
        requireSignature: true,
      );
      final installer = FakeUpdateInstaller();
      final controller = UpdateController(
        client: client,
        installer: installer,
        currentVersion: '1.0.0',
        platformCandidates: const ['windows-x86_64'],
        onQuitAfterInstall: () async {},
      );

      try {
        final check = await controller.checkForUpdate();
        expect(check.status, UpdateCheckStatus.failed);
        expect(check.errorMessage, contains('完整性'));

        final ok = await controller.downloadAndInstall(
          result: check,
          quitAfterLaunch: false,
        );

        expect(ok, isFalse);
        expect(controller.downloadedFile, isNull);
        expect(controller.isDownloading, isFalse);
        expect(controller.lastError, contains('没有可安装'));
        expect(installer.lastFile, isNull);
        expect(dir.listSync().whereType<File>(), isEmpty);
      } finally {
        controller.dispose();
      }
    });

    test('sha256 不匹配：删除下载包且不拉起安装器', () async {
      final mock = MockClient((request) async {
        if (request.url.path.endsWith('.json')) {
          return http.Response(
            jsonEncode({
              'version': '9.9.9',
              'platforms': {
                'windows-x86_64': {
                  'url': 'https://example.com/setup.exe',
                  'sha256': sha256HexOfBytes(utf8.encode('original-installer')),
                },
              },
            }),
            200,
          );
        }
        return http.Response.bytes(utf8.encode('tampered-installer'), 200);
      });
      final installer = FakeUpdateInstaller();
      final controller = UpdateController(
        client: UpdateClient(
          client: mock,
          manifestUrl: 'https://example.com/latest.json',
          downloadDirectory: dir,
          requireSignature: true,
        ),
        installer: installer,
        currentVersion: '1.0.0',
        platformCandidates: const ['windows-x86_64'],
        onQuitAfterInstall: () async {},
      );
      addTearDown(controller.dispose);
      final check = await controller.checkForUpdate();
      expect(check.hasUpdate, isTrue);
      final ok = await controller.downloadAndInstall(
        result: check,
        quitAfterLaunch: false,
      );
      expect(ok, isFalse);
      expect(controller.downloadedFile, isNull);
      expect(controller.isDownloading, isFalse);
      expect(controller.lastError, contains('完整性校验失败'));
      expect(installer.lastFile, isNull);
      expect(dir.listSync().whereType<File>(), isEmpty);
    });

    test('合法路径：下载成功并拉起安装器（假安装器）', () async {
      // 本用例用匹配的 sha256 验证控制器的安装接线。
      final payload = utf8.encode('ok-installer');
      final mock = MockClient((request) async {
        if (request.url.path.endsWith('.json')) {
          return http.Response(
            jsonEncode({
              'version': '9.9.9',
              'notes': 'test',
              'pub_date': '2026-09-08T00:00:00.000Z',
              'platforms': {
                'windows-x86_64': {
                  'url': 'https://example.com/setup.exe',
                  'sha256': sha256HexOfBytes(payload),
                },
              },
            }),
            200,
          );
        }
        return http.Response.bytes(payload, 200);
      });

      final client = UpdateClient(
        client: mock,
        manifestUrl: 'https://example.com/latest.json',
        downloadDirectory: dir,
        requireSignature: true,
      );
      final installer = FakeUpdateInstaller();
      final controller = UpdateController(
        client: client,
        installer: installer,
        currentVersion: '1.0.0',
        platformCandidates: const ['windows-x86_64'],
        onQuitAfterInstall: () async {},
      );

      try {
        final check = await controller.checkForUpdate();
        final ok = await controller.downloadAndInstall(
          result: check,
          quitAfterLaunch: false,
        );
        expect(ok, isTrue);
        expect(controller.downloadedFile, isNotNull);
        expect(installer.lastFile?.path, controller.downloadedFile!.path);
        expect(controller.lastError, isNull);
      } finally {
        controller.dispose();
      }
    });
  });
}
