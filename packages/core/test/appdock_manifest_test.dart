import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const sha =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  final versions = [
    {
      'tagName': 'v1.0.7',
      'body': '旧说明',
      'isPrerelease': false,
      'publishedAt': '2026-09-01T00:00:00.000Z',
      'assets': [
        {
          'name': 'AI.Studio_1.0.7_x64-setup.exe',
          'platform': 'windows',
          'arch': 'x64',
          'checksumSha256': sha,
          'downloadUrl': '/api/v1/public/apps/ai-studio/assets/old/download',
        },
      ],
    },
    {
      'tagName': 'v1.0.9-beta',
      'isPrerelease': true,
      'assets': [
        {
          'name': 'beta.exe',
          'platform': 'windows',
          'arch': 'x64',
          'checksumSha256': sha,
          'downloadUrl': '/api/v1/public/apps/ai-studio/assets/beta/download',
        },
      ],
    },
    {
      'tagName': 'v1.0.8',
      'body': '修复说明',
      'isPrerelease': false,
      'publishedAt': '2026-09-20T00:00:00.000Z',
      'assets': [
        {
          'name': 'AI.Studio_1.0.8_x64-setup.exe',
          'platform': 'windows',
          'arch': 'x64',
          'size': 12,
          'checksumSha256': sha,
          'downloadUrl': '/api/v1/public/apps/ai-studio/assets/win/download',
        },
        {
          'name': 'AI.Studio_1.0.8_aarch64.zip',
          'platform': 'macos',
          'arch': 'arm64',
          'checksumSha256': sha,
          'downloadUrl':
              'https://appdock.livancen.top/api/v1/public/apps/ai-studio/assets/mac/download',
        },
        {
          'name': 'AI.Studio_1.0.8_arm64-v8a.apk',
          'platform': 'android',
          'arch': 'arm64',
          'checksumSha256': sha,
          'downloadUrl': '/api/v1/public/apps/ai-studio/assets/apk/download',
        },
      ],
    },
  ];

  group('updateManifestFromAppDockVersions', () {
    test('picks highest stable and maps platforms', () {
      final manifest = updateManifestFromAppDockVersions(
        versions,
        baseUrl: kAppDockBaseUrl,
      );
      expect(manifest.version, '1.0.8');
      expect(manifest.notes, '修复说明');
      expect(
        manifest.platforms['windows-x86_64']!.url,
        '$kAppDockBaseUrl/api/v1/public/apps/ai-studio/assets/win/download',
      );
      expect(manifest.platforms['windows-x86_64']!.sha256, sha);
      expect(
        manifest.platforms['darwin-aarch64']!.url,
        contains('/assets/mac/download'),
      );
      expect(
        manifest.platforms['arm64-v8a']!.url,
        contains('/assets/apk/download'),
      );
      expect(manifest.platforms.containsKey('windows-x86_64'), isTrue);
      expect(manifest.resolvePlatform(const ['linux-x86_64']), isNull);
    });

    test('skips prerelease-only feeds as empty latest', () {
      final manifest = updateManifestFromAppDockVersions(
        [
          {
            'tagName': 'v9.0.0',
            'isPrerelease': true,
            'assets': <Object>[],
          },
        ],
        baseUrl: kAppDockBaseUrl,
      );
      expect(manifest.version, '0.0.0');
      expect(manifest.platforms, isEmpty);
    });
  });

  group('UpdateClient AppDock', () {
    test('available from versions array and absolute download', () async {
      final mock = MockClient((request) async {
        expect(request.url.path, '/api/v1/public/apps/ai-studio/versions');
        return http.Response.bytes(
          utf8.encode(jsonEncode(versions)),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final client = UpdateClient(
        client: mock,
        manifestUrl: kDesktopUpdateManifestUrl,
      );
      final result = await client.checkForUpdate(
        currentVersion: '1.0.0',
        platformCandidates: const ['windows-x86_64'],
      );
      expect(result.status, UpdateCheckStatus.available);
      expect(result.latestVersion, '1.0.8');
      expect(result.asset!.url, startsWith('https://appdock.livancen.top/'));
      expect(result.asset!.sha256, sha);
      client.close();
    });

    test('failed when matched asset has no sha256', () async {
      final mock = MockClient((request) async {
        return http.Response(
          jsonEncode([
            {
              'tagName': 'v2.0.0',
              'isPrerelease': false,
              'assets': [
                {
                  'name': 'setup.exe',
                  'platform': 'windows',
                  'arch': 'x64',
                  'downloadUrl': '/api/v1/public/apps/ai-studio/assets/x/download',
                },
              ],
            },
          ]),
          200,
        );
      });
      final client = UpdateClient(
        client: mock,
        manifestUrl: kDesktopUpdateManifestUrl,
      );
      final result = await client.checkForUpdate(
        currentVersion: '1.0.0',
        platformCandidates: const ['windows-x86_64'],
      );
      expect(result.status, UpdateCheckStatus.failed);
      expect(result.errorMessage, contains('完整性'));
      client.close();
    });

    test('403 password body asks for access code', () async {
      final mock = MockClient((request) async {
        return http.Response.bytes(
          utf8.encode(
            '{"error":{"code":"PASSWORD_REQUIRED","message":"需要访问口令"}}',
          ),
          403,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final client = UpdateClient(
        client: mock,
        manifestUrl: kDesktopUpdateManifestUrl,
      );
      final result = await client.checkForUpdate(
        currentVersion: '1.0.0',
        platformCandidates: const ['windows-x86_64'],
      );
      expect(result.status, UpdateCheckStatus.failed);
      expect(result.errorMessage, kUpdateAccessRequiredMessage);
      client.close();
    });

    test('saved session cookie is sent and unlock persists it', () async {
      final store = MemorySecretStore();
      final access = AppDockAccessSession(
        store: store,
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/public/apps/ai-studio/unlock');
          return http.Response(
            '{"ok":true}',
            200,
            headers: const {
              'set-cookie': 'access_session=sess-1; Path=/; HttpOnly',
            },
          );
        }),
      );
      await access.unlock('dock_test');
      expect(access.headers['Cookie'], 'access_session=sess-1');
      expect(await store.read(kAppDockAccessSessionKey), 'sess-1');

      final mock = MockClient((request) async {
        expect(request.headers['Cookie'], 'access_session=sess-1');
        return http.Response.bytes(
          utf8.encode(jsonEncode(versions)),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final client = UpdateClient(
        client: mock,
        manifestUrl: kDesktopUpdateManifestUrl,
        accessSession: access,
      );
      final result = await client.checkForUpdate(
        currentVersion: '1.0.0',
        platformCandidates: const ['windows-x86_64'],
      );
      expect(result.status, UpdateCheckStatus.available);
      client.close();
      access.close();
    });

    test('download verifies sha256', () async {
      final bytes = utf8.encode('appdock-installer');
      final digest = sha256HexOfBytes(bytes);
      final mock = MockClient((request) async {
        return http.Response.bytes(bytes, 200);
      });
      final dir = await Directory.systemTemp.createTemp('ai_appdock_');
      final client = UpdateClient(
        client: mock,
        manifestUrl: kDesktopUpdateManifestUrl,
        downloadDirectory: dir,
      );
      final file = await client.downloadInstaller(
        PlatformAsset(
          url: '$kAppDockBaseUrl/api/v1/public/apps/ai-studio/assets/win/download',
          sha256: digest,
        ),
        fileNameHint: 'AI.Studio_setup.exe',
      );
      expect(await file.exists(), isTrue);
      await file.delete();
      await dir.delete(recursive: true);
      client.close();
    });
  });
}
