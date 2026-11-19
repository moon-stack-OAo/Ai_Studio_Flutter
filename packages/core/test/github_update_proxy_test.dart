import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const assetUrl =
      'https://github.com/moon-stack-OAo/Ai_Studio_Flutter/releases/download/v1.0.8/setup.exe';
  final bytes = utf8.encode('github-installer');
  final digest = sha256HexOfBytes(bytes);
  final manifest = jsonEncode({
    'version': '1.0.8',
    'platforms': {
      'windows-x86_64': {'url': assetUrl, 'signature': 'sig'},
      'android-arm64-v8a': {'url': assetUrl, 'sha256': digest},
    },
  });

  test(
    'desktop and Android defaults use separate accelerated GitHub manifests',
    () async {
      final requested = <String>[];
      final mock = MockClient((request) async {
        requested.add(request.url.toString());
        return http.Response(manifest, 200);
      });
      final desktop = UpdateClient(client: mock);
      final android = AndroidUpdateClient(client: mock);
      await desktop.fetchManifest();
      await android.updateClient.fetchManifest();
      expect(requested, [
        '$kGithubUpdateProxyPrefix$kGithubDesktopUpdateManifestUrl',
        '$kGithubUpdateProxyPrefix$kGithubAndroidUpdateManifestUrl',
      ]);
      desktop.close();
      android.close();
    },
  );

  for (final status in [403, 404, 429, 502, 503]) {
    test('manifest proxy HTTP $status falls back to direct GitHub', () async {
      final requested = <String>[];
      final mock = MockClient((request) async {
        requested.add(request.url.toString());
        return request.url.host == 'ghfast.top'
            ? http.Response('proxy unavailable', status)
            : http.Response(manifest, 200);
      });
      final client = UpdateClient(client: mock);
      expect((await client.fetchManifest()).version, '1.0.8');
      expect(requested, [
        kDesktopUpdateManifestUrl,
        kGithubDesktopUpdateManifestUrl,
      ]);
      client.close();
    });
  }

  test(
    'Android manifest network failure falls back to Android direct URL',
    () async {
      final requested = <String>[];
      final mock = MockClient((request) async {
        requested.add(request.url.toString());
        if (request.url.host == 'ghfast.top') {
          throw const SocketException('connection failed');
        }
        return http.Response(manifest, 200);
      });
      final client = AndroidUpdateClient(client: mock);
      await client.updateClient.fetchManifest();
      expect(requested, [
        kAndroidUpdateManifestUrl,
        kGithubAndroidUpdateManifestUrl,
      ]);
      client.close();
    },
  );

  for (final url in [assetUrl, '$kGithubUpdateProxyPrefix$assetUrl']) {
    test('download uses proxy once then direct on failure: $url', () async {
      final dir = await Directory.systemTemp.createTemp('github_proxy_test_');
      addTearDown(() => dir.delete(recursive: true));
      final requested = <String>[];
      final client = UpdateClient(
        downloadDirectory: dir,
        client: MockClient((request) async {
          requested.add(request.url.toString());
          return request.url.host == 'ghfast.top'
              ? http.Response('bad gateway', 502)
              : http.Response.bytes(bytes, 200);
        }),
      );
      final file = await client.downloadInstaller(
        PlatformAsset(url: url, sha256: digest),
      );
      expect(await file.readAsBytes(), bytes);
      expect(requested, ['$kGithubUpdateProxyPrefix$assetUrl', assetUrl]);
      client.close();
    });
  }

  test(
    'successful accelerated download does not request direct GitHub',
    () async {
      final dir = await Directory.systemTemp.createTemp('github_proxy_test_');
      addTearDown(() => dir.delete(recursive: true));
      final requested = <String>[];
      final client = UpdateClient(
        downloadDirectory: dir,
        client: MockClient((request) async {
          requested.add(request.url.toString());
          return http.Response.bytes(bytes, 200);
        }),
      );
      await client.downloadInstaller(
        PlatformAsset(url: assetUrl, sha256: digest),
      );
      expect(requested, ['$kGithubUpdateProxyPrefix$assetUrl']);
      client.close();
    },
  );

  test(
    'integrity failure blocks without fallback and deletes the package',
    () async {
      final dir = await Directory.systemTemp.createTemp('github_proxy_test_');
      addTearDown(() => dir.delete(recursive: true));
      var hits = 0;
      final client = UpdateClient(
        downloadDirectory: dir,
        client: MockClient((request) async {
          hits++;
          return http.Response.bytes(utf8.encode('tampered'), 200);
        }),
      );
      await expectLater(
        client.downloadInstaller(PlatformAsset(url: assetUrl, sha256: digest)),
        throwsA(isA<UpdateException>()),
      );
      expect(hits, 1);
      expect(await dir.list().toList(), isEmpty);
      client.close();
    },
  );

  test('non-GitHub asset is not rewritten', () async {
    final dir = await Directory.systemTemp.createTemp('github_proxy_test_');
    addTearDown(() => dir.delete(recursive: true));
    const url = 'https://example.com/setup.exe';
    final client = UpdateClient(
      downloadDirectory: dir,
      client: MockClient((request) async {
        expect(request.url.toString(), url);
        return http.Response.bytes(bytes, 200);
      }),
    );
    await client.downloadInstaller(PlatformAsset(url: url, sha256: digest));
    client.close();
  });
}
