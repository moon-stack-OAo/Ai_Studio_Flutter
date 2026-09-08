import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_material/update/mobile_update_controller.dart';

void main() {
  group('MobileUpdateController 校验失败阻断', () {
    late Directory dir;
    final apkBytes = Uint8List.fromList(List<int>.generate(64, (i) => i));
    final apkSha = sha256HexOfBytes(apkBytes);

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('ai_studio_mupd_');
    });

    tearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    test('sha256 不匹配：downloadAndInstall 失败且不调起安装器', () async {
      final mock = MockClient((request) async {
        if (request.url.path.endsWith('.json')) {
          return http.Response(
            jsonEncode({
              'version': '9.9.9',
              'notes': 'apk',
              'pub_date': '2026-09-08T00:00:00.000Z',
              'platforms': {
                'aarch64-linux-android': {
                  'url': 'https://example.com/app.apk',
                  'sha256': apkSha,
                },
              },
            }),
            200,
          );
        }
        return http.Response.bytes(apkBytes, 200);
      });

      final android = AndroidUpdateClient(
        client: mock,
        manifestUrl: 'https://example.com/android-latest.json',
        downloadDirectory: dir,
      );
      final installer = FakeAndroidApkInstaller();
      final controller = MobileUpdateController(
        androidClient: android,
        apkInstaller: installer,
        currentVersion: '1.0.0',
        platformCandidates: const ['aarch64-linux-android'],
        forceAndroid: true,
      );

      try {
        final check = await controller.checkForUpdate();
        expect(check.hasUpdate, isTrue);

        // 用错误 hash 的 asset 覆盖，模拟篡改包 / 清单不一致。
        final tampered = UpdateCheckResult.available(
          currentVersion: check.currentVersion,
          manifest: check.manifest!,
          asset: PlatformAsset(
            url: check.asset!.url,
            sha256: '0' * 64,
          ),
          matchedPlatformKey: check.matchedPlatformKey!,
        );

        final ok = await controller.downloadAndInstall(result: tampered);
        expect(ok, isFalse);
        expect(controller.downloadedFile, isNull);
        expect(controller.isDownloading, isFalse);
        expect(controller.lastError, isNotNull);
        expect(installer.lastFile, isNull);
        expect(dir.listSync().whereType<File>(), isEmpty);
      } finally {
        controller.dispose();
      }
    });

    test('校验通过：进入可安装态并调起 FakeAndroidApkInstaller', () async {
      final mock = MockClient((request) async {
        if (request.url.path.endsWith('.json')) {
          return http.Response(
            jsonEncode({
              'version': '9.9.9',
              'notes': 'apk',
              'pub_date': '2026-09-08T00:00:00.000Z',
              'platforms': {
                'aarch64-linux-android': {
                  'url': 'https://example.com/app.apk',
                  'sha256': apkSha,
                },
              },
            }),
            200,
          );
        }
        return http.Response.bytes(apkBytes, 200);
      });

      final android = AndroidUpdateClient(
        client: mock,
        manifestUrl: 'https://example.com/android-latest.json',
        downloadDirectory: dir,
      );
      final installer = FakeAndroidApkInstaller();
      final controller = MobileUpdateController(
        androidClient: android,
        apkInstaller: installer,
        currentVersion: '1.0.0',
        platformCandidates: const ['aarch64-linux-android'],
        forceAndroid: true,
      );

      try {
        final check = await controller.checkForUpdate();
        final ok = await controller.downloadAndInstall(result: check);
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
