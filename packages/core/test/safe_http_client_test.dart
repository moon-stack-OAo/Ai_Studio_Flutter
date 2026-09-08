import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('redirect helpers', () {
    test('shouldFollowRedirect matches dart:io rules', () {
      expect(shouldFollowRedirect('GET', 301), isTrue);
      expect(shouldFollowRedirect('GET', 302), isTrue);
      expect(shouldFollowRedirect('HEAD', 307), isTrue);
      expect(shouldFollowRedirect('POST', 303), isTrue);
      expect(shouldFollowRedirect('POST', 302), isFalse);
      expect(shouldFollowRedirect('PUT', 301), isFalse);
      expect(shouldFollowRedirect('GET', 200), isFalse);
    });

    test('redirectRequestMethod switches POST 303 to GET', () {
      expect(redirectRequestMethod('POST', 303), 'GET');
      expect(redirectRequestMethod('GET', 302), 'GET');
      expect(redirectRequestMethod('HEAD', 303), 'HEAD');
    });

    test('resolveRedirectUri resolves relative Location', () {
      final next = resolveRedirectUri(
        Uri.parse('https://cdn.example.com/a/b'),
        '../safe.bin',
      );
      expect(next.toString(), 'https://cdn.example.com/safe.bin');
    });

    test('assertSafeRedirectTarget blocks metadata', () {
      expect(
        () => assertSafeRedirectTarget(
          Uri.parse('http://169.254.169.254/latest/meta-data/'),
        ),
        throwsA(isA<UrlSafetyException>()),
      );
      expect(
        () => assertSafeRedirectTarget(Uri.parse('https://example.com/ok')),
        returnsNormally,
      );
    });
  });

  group('SafeRedirectHttpClient', () {
    test('blocks redirect to metadata host', () async {
      final inner = MockClient((request) async {
        if (request.url.path == '/start') {
          return http.Response(
            '',
            302,
            headers: {'location': 'http://169.254.169.254/latest/meta-data/'},
            request: request,
          );
        }
        fail('must not follow unsafe redirect: ${request.url}');
      });
      final client = SafeRedirectHttpClient(inner);
      addTearDown(client.close);

      await expectLater(
        client.get(Uri.parse('https://updates.example.com/start')),
        throwsA(
          isA<UrlSafetyException>().having(
            (e) => e.message,
            'message',
            contains('云元数据'),
          ),
        ),
      );
    });

    test('blocks redirect to file scheme', () async {
      final inner = MockClient((request) async {
        return http.Response(
          '',
          301,
          headers: {'location': 'file:///etc/passwd'},
          request: request,
        );
      });
      final client = SafeRedirectHttpClient(inner);
      addTearDown(client.close);

      await expectLater(
        client.get(Uri.parse('https://updates.example.com/pkg')),
        throwsA(isA<UrlSafetyException>()),
      );
    });

    test('follows safe redirect chain', () async {
      final seen = <String>[];
      final inner = MockClient((request) async {
        seen.add('${request.method} ${request.url}');
        if (request.url.path == '/one') {
          return http.Response(
            '',
            302,
            headers: {'location': '/two'},
            request: request,
          );
        }
        if (request.url.path == '/two') {
          return http.Response(
            'ok-body',
            200,
            headers: {'content-type': 'text/plain'},
            request: request,
          );
        }
        fail('unexpected ${request.url}');
      });
      final client = SafeRedirectHttpClient(inner);
      addTearDown(client.close);

      final response =
          await client.get(Uri.parse('https://cdn.example.com/one'));
      expect(response.statusCode, 200);
      expect(response.body, 'ok-body');
      expect(seen, [
        'GET https://cdn.example.com/one',
        'GET https://cdn.example.com/two',
      ]);
    });

    test('POST 303 becomes GET on next hop', () async {
      final seen = <String>[];
      final inner = MockClient((request) async {
        seen.add('${request.method} ${request.url.path}');
        if (request.method == 'POST' && request.url.path == '/submit') {
          return http.Response(
            '',
            303,
            headers: {'location': '/result'},
            request: request,
          );
        }
        if (request.method == 'GET' && request.url.path == '/result') {
          return http.Response('done', 200, request: request);
        }
        fail('unexpected ${request.method} ${request.url}');
      });
      final client = SafeRedirectHttpClient(inner);
      addTearDown(client.close);

      final response = await client.post(
        Uri.parse('https://api.example.com/submit'),
        body: '{"a":1}',
      );
      expect(response.statusCode, 200);
      expect(response.body, 'done');
      expect(seen, ['POST /submit', 'GET /result']);
    });

    test('createSafeHttpClient rejects unsafe initial URL', () async {
      final client = createSafeHttpClient(
        inner: MockClient((_) async => http.Response('no', 200)),
      );
      addTearDown(client.close);

      await expectLater(
        client.get(Uri.parse('http://169.254.169.254/')),
        throwsA(isA<UrlSafetyException>()),
      );
    });

    test('respects followRedirects false', () async {
      final inner = MockClient((request) async {
        expect(request.followRedirects, isFalse);
        return http.Response(
          '',
          302,
          headers: {'location': 'http://169.254.169.254/'},
          request: request,
          isRedirect: true,
        );
      });
      final client = SafeRedirectHttpClient(inner);
      addTearDown(client.close);

      final req = http.Request('GET', Uri.parse('https://cdn.example.com/x'))
        ..followRedirects = false;
      final response = await client.send(req);
      expect(response.statusCode, 302);
    });
  });
}
