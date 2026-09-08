import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:desktop_fluent/update/update_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('UpdateController 验签失败阻断', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('ai_studio_upd_ctrl_');
    });

    tearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    test('缺签名：downloadAndInstall 失败且不进入可安装态', () async {
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
        return http.Response.bytes(payload, 200, headers: {
          'content-length': '${payload.length}',
        });
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
        expect(check.hasUpdate, isTrue);
        expect(check.asset, isNotNull);

        final ok = await controller.downloadAndInstall(
          result: check,
          quitAfterLaunch: false,
        );

        expect(ok, isFalse);
        expect(controller.downloadedFile, isNull);
        expect(controller.isDownloading, isFalse);
        expect(controller.lastError, contains('缺少签名'));
        expect(installer.lastFile, isNull);
        expect(dir.listSync().whereType<File>(), isEmpty);
      } finally {
        controller.dispose();
      }
    });

    test('合法路径：下载成功并拉起安装器（假安装器）', () async {
      // 本用例关闭验签，只验证控制器「可安装」态接线；真验签在 core minisign 测试。
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
                  'signature': 'ignored-when-requireSignature-false',
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
        requireSignature: false,
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
