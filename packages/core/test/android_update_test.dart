import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final apkBytes = Uint8List.fromList(List<int>.generate(128, (i) => i));
  final apkSha = sha256HexOfBytes(apkBytes);

  final androidFixture = {
    'version': '1.0.8',
    'notes': 'Android sideload notes',
    'pub_date': '2026-09-04T12:00:00.000Z',
    'platforms': {
      'aarch64-linux-android': {
        'url':
            'https://github.com/moon-stack-OAo/AiStudio/releases/download/v1.0.8/app-arm64.apk',
        'sha256': apkSha,
        'size': apkBytes.length,
      },
      'arm64-v8a': {
        'url':
            'https://github.com/moon-stack-OAo/AiStudio/releases/download/v1.0.8/app-arm64.apk',
        'sha256': apkSha,
      },
    },
  };

  group('PlatformAsset sha256', () {
    test('parses sha256 and size from android asset', () {
      final m = UpdateManifest.fromJson(androidFixture);
      final asset = m.platforms['aarch64-linux-android']!;
      expect(asset.url, contains('.apk'));
      expect(asset.sha256, apkSha);
      expect(asset.size, apkBytes.length);
    });
  });

  group('androidUpdatePlatformCandidates', () {
    test('default prefers aarch64-linux-android then arm64-v8a', () {
      final keys = androidUpdatePlatformCandidates();
      expect(keys.first, 'aarch64-linux-android');
      expect(keys, contains('arm64-v8a'));
    });

    test('abiHint armeabi prefers 32-bit first', () {
      final keys = androidUpdatePlatformCandidates(abiHint: 'armeabi-v7a');
      expect(keys.first, 'armeabi-v7a');
    });

    test('abiHint x86_64 prefers emulator abi first', () {
      final keys = androidUpdatePlatformCandidates(abiHint: 'x86_64');
      expect(keys.first, 'x86_64');
      expect(keys, contains('x86_64-linux-android'));
    });

    test('normalizeAndroidAbiHint maps common aliases', () {
      expect(normalizeAndroidAbiHint('android_arm64'), 'arm64-v8a');
      expect(normalizeAndroidAbiHint('armeabi-v7a'), 'armeabi-v7a');
      expect(normalizeAndroidAbiHint('android_x64'), 'x86_64');
    });
  });

  group('sha256 util', () {
    test('isValidSha256 / requireValidSha256', () {
      expect(isValidSha256(apkSha), isTrue);
      expect(isValidSha256('abc'), isFalse);
      expect(requireValidSha256('  ${apkSha.toUpperCase()}  '), apkSha);
      expect(
        () => requireValidSha256('not-a-hash'),
        throwsA(isA<UpdateException>()),
      );
    });

    test('verifyBytesSha256 accepts match and rejects mismatch', () {
      verifyBytesSha256(apkBytes, apkSha);
      expect(
        () => verifyBytesSha256(apkBytes, '0' * 64),
        throwsA(isA<UpdateException>()),
      );
    });

    test('verifyFileSha256', () async {
      final dir = await Directory.systemTemp.createTemp('ai_sha_');
      final file = File('${dir.path}${Platform.pathSeparator}a.bin');
      await file.writeAsBytes(apkBytes);
      await verifyFileSha256(file, apkSha);
      await expectLater(
        verifyFileSha256(file, '1' * 64),
        throwsA(isA<UpdateException>()),
      );
      // mismatch deletes file
      expect(await file.exists(), isFalse);
      await dir.delete(recursive: true);
    });
  });

  group('AndroidUpdateClient', () {
    test('available when remote newer and sha256 present', () async {
      final mock = MockClient((request) async {
        return http.Response(jsonEncode(androidFixture), 200);
      });
      final client = AndroidUpdateClient(
        client: mock,
        manifestUrl: 'https://example.com/android-latest.json',
      );
      final result = await client.checkForUpdate(currentVersion: '1.0.0');
      expect(result.status, UpdateCheckStatus.available);
      expect(result.latestVersion, '1.0.8');
      expect(result.matchedPlatformKey, 'aarch64-linux-android');
      expect(isValidSha256(result.asset!.sha256), isTrue);
      client.close();
    });

    test('upToDate reuses version compare', () async {
      final mock = MockClient((request) async {
        return http.Response(jsonEncode(androidFixture), 200);
      });
      final client = AndroidUpdateClient(
        client: mock,
        manifestUrl: 'https://example.com/android-latest.json',
      );
      final result = await client.checkForUpdate(currentVersion: '1.0.8');
      expect(result.status, UpdateCheckStatus.upToDate);
      expect(isRemoteNewer('1.0.8', '1.0.8'), isFalse);
      client.close();
    });

    test('failed when sha256 missing on available update', () async {
      final bad = {
        'version': '2.0.0',
        'platforms': {
          'aarch64-linux-android': {
            'url': 'https://example.com/app.apk',
          },
        },
      };
      final mock = MockClient((request) async {
        return http.Response(jsonEncode(bad), 200);
      });
      final client = AndroidUpdateClient(
        client: mock,
        manifestUrl: 'https://example.com/android-latest.json',
      );
      final result = await client.checkForUpdate(currentVersion: '1.0.0');
      expect(result.status, UpdateCheckStatus.failed);
      expect(result.errorMessage, contains('完整性'));
      client.close();
    });

    test('downloadAndVerify checks sha256', () async {
      final mock = MockClient((request) async {
        if (request.url.path.endsWith('.json')) {
          return http.Response(jsonEncode(androidFixture), 200);
        }
        return http.Response.bytes(apkBytes, 200, headers: {
          'content-length': '${apkBytes.length}',
        });
      });
      final dir = await Directory.systemTemp.createTemp('ai_apk_');
      final client = AndroidUpdateClient(
        client: mock,
        manifestUrl: 'https://example.com/android-latest.json',
        downloadDirectory: dir,
      );
      final check = await client.checkForUpdate(currentVersion: '1.0.0');
      expect(check.hasUpdate, isTrue);
      final file = await client.downloadAndVerify(check.asset!);
      expect(await file.exists(), isTrue);
      expect(await file.length(), apkBytes.length);
      await verifyFileSha256(file, apkSha);
      await file.delete();
      await dir.delete(recursive: true);
      client.close();
    });

    test('downloadAndVerify rejects bad hash and deletes file', () async {
      final mock = MockClient((request) async {
        return http.Response.bytes(apkBytes, 200);
      });
      final dir = await Directory.systemTemp.createTemp('ai_apk_bad_');
      final client = AndroidUpdateClient(
        client: mock,
        manifestUrl: 'https://example.com/android-latest.json',
        downloadDirectory: dir,
      );
      expect(
        () => client.downloadAndVerify(
          PlatformAsset(
            url: 'https://example.com/app.apk',
            sha256: '0' * 64,
          ),
        ),
        throwsA(isA<UpdateException>()),
      );
      final leftovers = dir.listSync().whereType<File>().toList();
      expect(leftovers, isEmpty);
      await dir.delete(recursive: true);
      client.close();
    });

    test('downloadVerifyAndInstall uses AndroidApkInstaller', () async {
      final mock = MockClient((request) async {
        return http.Response.bytes(apkBytes, 200);
      });
      final dir = await Directory.systemTemp.createTemp('ai_apk_inst_');
      final client = AndroidUpdateClient(
        client: mock,
        manifestUrl: 'https://example.com/android-latest.json',
        downloadDirectory: dir,
      );
      final installer = FakeAndroidApkInstaller();
      final file = await client.downloadVerifyAndInstall(
        PlatformAsset(
          url: 'https://example.com/app.apk',
          sha256: apkSha,
        ),
        installer,
      );
      expect(installer.lastFile?.path, file.path);
      await file.delete();
      await dir.delete(recursive: true);
      client.close();
    });
  });

  group('desktop UpdateClient still green with sha256 field', () {
    test('desktop asset without sha256 still parses', () {
      final m = UpdateManifest.fromJson({
        'version': '1.0.7',
        'platforms': {
          'windows-x86_64': {
            'url': 'https://example.com/setup.exe',
            'signature': 'sig',
          },
        },
      });
      expect(m.platforms['windows-x86_64']!.sha256, isEmpty);
      expect(m.platforms['windows-x86_64']!.signature, 'sig');
    });
  });
}
