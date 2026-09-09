import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_material/update/mobile_update_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MobileUpdateController 校验失败阻断', () {
    late Directory dir;
    final apkBytes = Uint8List.fromList(List<int>.generate(64, (i) => i));
    final apkSha = sha256HexOfBytes(apkBytes);

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      dir = await Directory.systemTemp.createTemp('ai_studio_mupd_');
    });

    tearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    test('sha256 不匹配：downloadAndInstall 失败且不调起安装器', () async {
      // 清单声称合法格式 sha256，但与实际 APK 字节不一致；
      // downloadAndInstall 会重新 check，因此不能再靠外部篡改 asset。
      final wrongSha = '0' * 64;
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
                  'sha256': wrongSha,
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
        expect(check.asset?.sha256, wrongSha);

        final ok = await controller.downloadAndInstall(result: check);
        expect(ok, isFalse);
        expect(controller.downloadedFile, isNull);
        expect(controller.isDownloading, isFalse);
        expect(controller.lastError, isNotNull);
        expect(installer.lastFile, isNull);
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

  group('MobileUpdateController silent / prefs', () {
    late Directory dir;
    final apkBytes = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
    final apkSha = sha256HexOfBytes(apkBytes);

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      dir = await Directory.systemTemp.createTemp('ai_studio_mupd_prefs_');
    });

    tearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    AndroidUpdateClient _client(MockClient mock) {
      return AndroidUpdateClient(
        client: mock,
        manifestUrl: 'https://example.com/android-latest.json',
        downloadDirectory: dir,
      );
    }

    MockClient _manifestMock({required String version}) {
      return MockClient((request) async {
        if (request.url.path.endsWith('.json')) {
          return http.Response(
            jsonEncode({
              'version': version,
              'notes': 'release notes',
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
    }

    test('silent + 已跳过同版本：不写 available，不改 lastCheck', () async {
      final prefs = UpdatePrefs(prefs: await SharedPreferences.getInstance());
      await prefs.skipUpdateVersion('9.9.9');
      final controller = MobileUpdateController(
        androidClient: _client(_manifestMock(version: '9.9.9')),
        apkInstaller: FakeAndroidApkInstaller(),
        updatePrefs: prefs,
        currentVersion: '1.0.0',
        platformCandidates: const ['aarch64-linux-android'],
        forceAndroid: true,
      );

      try {
        final result = await controller.checkForUpdate(silent: true);
        expect(result.hasUpdate, isTrue);
        expect(controller.lastCheck, isNull);
        expect(controller.hasAvailableUpdate, isFalse);
        expect(prefs.availableUpdateVersion, isNull);
      } finally {
        controller.dispose();
      }
    });

    test('!silent：clearSkipped 并 setAvailableUpdate', () async {
      final prefs = UpdatePrefs(prefs: await SharedPreferences.getInstance());
      await prefs.skipUpdateVersion('9.9.9');
      final controller = MobileUpdateController(
        androidClient: _client(_manifestMock(version: '9.9.9')),
        apkInstaller: FakeAndroidApkInstaller(),
        updatePrefs: prefs,
        currentVersion: '1.0.0',
        platformCandidates: const ['aarch64-linux-android'],
        forceAndroid: true,
      );

      try {
        final result = await controller.checkForUpdate(silent: false);
        expect(result.hasUpdate, isTrue);
        expect(controller.lastCheck?.hasUpdate, isTrue);
        expect(controller.hasAvailableUpdate, isTrue);
        expect(prefs.skippedUpdateVersion, isNull);
        expect(prefs.availableUpdateVersion, '9.9.9');
      } finally {
        controller.dispose();
      }
    });

    test('silent 失败：可记 lastError，但不写 lastCheck', () async {
      final mock = MockClient((request) async {
        throw const SocketException('network down');
      });
      final prefs = UpdatePrefs(prefs: await SharedPreferences.getInstance());
      final controller = MobileUpdateController(
        androidClient: _client(mock),
        apkInstaller: FakeAndroidApkInstaller(),
        updatePrefs: prefs,
        currentVersion: '1.0.0',
        platformCandidates: const ['aarch64-linux-android'],
        forceAndroid: true,
      );

      try {
        final result = await controller.checkForUpdate(silent: true);
        expect(result.status, UpdateCheckStatus.failed);
        expect(controller.lastCheck, isNull);
        expect(controller.lastError, isNotNull);
      } finally {
        controller.dispose();
      }
    });

    test('setAutoCheckUpdate / skipUpdateVersion 暴露 prefs', () async {
      final prefs = UpdatePrefs(prefs: await SharedPreferences.getInstance());
      final controller = MobileUpdateController(
        androidClient: _client(_manifestMock(version: '2.0.0')),
        apkInstaller: FakeAndroidApkInstaller(),
        updatePrefs: prefs,
        currentVersion: '1.0.0',
        platformCandidates: const ['aarch64-linux-android'],
        forceAndroid: true,
      );

      try {
        expect(controller.autoCheckUpdate, isTrue);
        await controller.setAutoCheckUpdate(false);
        expect(controller.autoCheckUpdate, isFalse);

        await controller.checkForUpdate(silent: false);
        expect(controller.hasAvailableUpdate, isTrue);

        await controller.skipUpdateVersion('2.0.0');
        expect(controller.hasAvailableUpdate, isFalse);
        expect(controller.lastCheck, isNull);
      } finally {
        controller.dispose();
      }
    });
  });
}
