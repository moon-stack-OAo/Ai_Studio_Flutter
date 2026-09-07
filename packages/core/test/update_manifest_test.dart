import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final fixture = {
    'version': '1.0.7',
    'notes': 'fix notes',
    'pub_date': '2026-09-03T07:21:40.354Z',
    'platforms': {
      'windows-x86_64': {
        'signature': 'sig-nsis',
        'url':
            'https://github.com/moon-stack-OAo/AiStudio/releases/download/v1.0.7/AI.Studio_1.0.7_x64-setup.exe',
      },
      'windows-x86_64-nsis': {
        'signature': 'sig-nsis',
        'url':
            'https://github.com/moon-stack-OAo/AiStudio/releases/download/v1.0.7/AI.Studio_1.0.7_x64-setup.exe',
      },
      'windows-x86_64-msi': {
        'signature': 'sig-msi',
        'url':
            'https://github.com/moon-stack-OAo/AiStudio/releases/download/v1.0.7/AI.Studio_1.0.7_x64_zh-CN.msi',
      },
      'darwin-aarch64': {
        'signature': 'sig-mac',
        'url':
            'https://github.com/moon-stack-OAo/AiStudio/releases/download/v1.0.7/AI.Studio_1.0.7_aarch64.app.tar.gz',
      },
    },
  };

  group('UpdateManifest.fromJson', () {
    test('parses Tauri latest.json fields', () {
      final m = UpdateManifest.fromJson(fixture);
      expect(m.version, '1.0.7');
      expect(m.notes, 'fix notes');
      expect(m.pubDate, '2026-09-03T07:21:40.354Z');
      expect(m.platforms.keys, containsAll(['windows-x86_64', 'darwin-aarch64']));
      expect(
        m.platforms['windows-x86_64']!.url,
        contains('x64-setup.exe'),
      );
      expect(m.platforms['windows-x86_64']!.signature, 'sig-nsis');
    });

    test('resolvePlatform prefers first candidate with url', () {
      final m = UpdateManifest.fromJson(fixture);
      final asset = m.resolvePlatform(const [
        'windows-x86_64',
        'windows-x86_64-nsis',
      ]);
      expect(asset, isNotNull);
      expect(asset!.url, contains('setup.exe'));
    });

    test('accepts body/date aliases', () {
      final m = UpdateManifest.fromJson({
        'version': '2.0.0',
        'body': 'changelog',
        'date': '2026-01-01',
        'platforms': {},
      });
      expect(m.notes, 'changelog');
      expect(m.pubDate, '2026-01-01');
    });
  });

  group('desktopUpdatePlatformCandidates', () {
    test('windows candidates include windows-x86_64', () {
      final keys = desktopUpdatePlatformCandidates(isWindows: true);
      expect(keys.first, 'windows-x86_64');
      expect(keys, contains('windows-x86_64-nsis'));
    });

    test('macos arm prefers darwin-aarch64', () {
      final keys = desktopUpdatePlatformCandidates(
        isMacOS: true,
        isWindows: false,
        isLinux: false,
        macArch: 'arm64',
      );
      expect(keys.first, 'darwin-aarch64');
    });
  });

  group('UpdateClient.checkForUpdate', () {
    test('notConfigured when url empty', () async {
      final client = UpdateClient(manifestUrl: '');
      final result = await client.checkForUpdate(currentVersion: '1.0.0');
      expect(result.status, UpdateCheckStatus.notConfigured);
      expect(result.hasUpdate, isFalse);
      client.close();
    });

    test('available when remote newer and platform matches', () async {
      final mock = MockClient((request) async {
        return http.Response(jsonEncode(fixture), 200, headers: {
          'content-type': 'application/json',
        });
      });
      final client = UpdateClient(
        client: mock,
        manifestUrl: 'https://example.com/latest.json',
      );
      final result = await client.checkForUpdate(
        currentVersion: '1.0.0+1',
        platformCandidates: const ['windows-x86_64'],
      );
      expect(result.status, UpdateCheckStatus.available);
      expect(result.latestVersion, '1.0.7');
      expect(result.matchedPlatformKey, 'windows-x86_64');
      expect(result.asset?.url, contains('setup.exe'));
      client.close();
    });

    test('upToDate when versions equal', () async {
      final mock = MockClient((request) async {
        return http.Response(jsonEncode(fixture), 200);
      });
      final client = UpdateClient(
        client: mock,
        manifestUrl: 'https://example.com/latest.json',
      );
      final result = await client.checkForUpdate(
        currentVersion: '1.0.7',
        platformCandidates: const ['windows-x86_64'],
      );
      expect(result.status, UpdateCheckStatus.upToDate);
      client.close();
    });

    test('noPlatformAsset when platform missing', () async {
      final mock = MockClient((request) async {
        return http.Response(jsonEncode(fixture), 200);
      });
      final client = UpdateClient(
        client: mock,
        manifestUrl: 'https://example.com/latest.json',
      );
      final result = await client.checkForUpdate(
        currentVersion: '1.0.0',
        platformCandidates: const ['linux-x86_64'],
      );
      expect(result.status, UpdateCheckStatus.noPlatformAsset);
      client.close();
    });

    test('failed on 404', () async {
      final mock = MockClient((request) async {
        return http.Response('not found', 404);
      });
      final client = UpdateClient(
        client: mock,
        manifestUrl: 'https://example.com/latest.json',
      );
      final result = await client.checkForUpdate(currentVersion: '1.0.0');
      expect(result.status, UpdateCheckStatus.failed);
      expect(result.errorMessage, contains('404'));
      client.close();
    });

    test('downloadInstaller writes file and reports progress', () async {
      final bytes = List<int>.generate(64, (i) => i);
      final mock = MockClient((request) async {
        return http.Response.bytes(bytes, 200, headers: {
          'content-length': '${bytes.length}',
        });
      });
      final dir = await Directory.systemTemp.createTemp('ai_studio_upd_test_');
      final client = UpdateClient(
        client: mock,
        manifestUrl: 'https://example.com/latest.json',
        downloadDirectory: dir,
        // 本用例只测下载写盘；验签另测。
        requireSignature: false,
      );
      UpdateDownloadProgress? last;
      final file = await client.downloadInstaller(
        const PlatformAsset(
          url: 'https://example.com/AI.Studio_1.0.7_x64-setup.exe',
        ),
        onProgress: (p) => last = p,
      );
      expect(await file.exists(), isTrue);
      expect(await file.length(), 64);
      expect(last?.received, 64);
      expect(last?.total, 64);
      await file.delete();
      await dir.delete(recursive: true);
      client.close();
    });
  });
}
