import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('proxyEnvValue / environmentHasHttpProxy', () {
    test('prefers lowercase over uppercase', () {
      expect(
        proxyEnvValue(
          {'http_proxy': 'http://a:1', 'HTTP_PROXY': 'http://b:2'},
          'http_proxy',
        ),
        'http://a:1',
      );
    });

    test('detects any proxy env', () {
      expect(environmentHasHttpProxy({}), isFalse);
      expect(
        environmentHasHttpProxy({'HTTPS_PROXY': 'http://127.0.0.1:7897'}),
        isTrue,
      );
    });
  });

  group('hostMatchesProxyOverride', () {
    test('exact and wildcard and <local>', () {
      expect(
        hostMatchesProxyOverride('localhost', 'localhost;127.*;<local>'),
        isTrue,
      );
      expect(hostMatchesProxyOverride('intranet', '<local>'), isTrue);
      expect(hostMatchesProxyOverride('github.com', '<local>'), isFalse);
      expect(hostMatchesProxyOverride('127.0.0.1', '127.*'), isTrue);
      expect(hostMatchesProxyOverride('192.168.1.2', '192.168.*'), isTrue);
      expect(hostMatchesProxyOverride('github.com', '192.168.*;10.*'), isFalse);
    });
  });

  group('pickWindowsProxyServer', () {
    test('plain host:port', () {
      expect(pickWindowsProxyServer('127.0.0.1:7897', 'https'), '127.0.0.1:7897');
    });

    test('scheme-specific list', () {
      expect(
        pickWindowsProxyServer(
          'http=127.0.0.1:7890;https=127.0.0.1:7897',
          'https',
        ),
        '127.0.0.1:7897',
      );
      expect(
        pickWindowsProxyServer(
          'http=127.0.0.1:7890;https=127.0.0.1:7897',
          'http',
        ),
        '127.0.0.1:7890',
      );
    });

    test('strips scheme prefix', () {
      expect(
        pickWindowsProxyServer('http://127.0.0.1:7897', 'https'),
        '127.0.0.1:7897',
      );
    });
  });

  group('resolveHttpProxy', () {
    test('env wins over windows', () {
      final result = resolveHttpProxy(
        Uri.parse('https://github.com/x'),
        environment: {'https_proxy': 'http://127.0.0.1:9999'},
        windows: const WindowsProxySettings(
          enabled: true,
          proxyServer: '127.0.0.1:7897',
        ),
      );
      expect(result, contains('127.0.0.1:9999'));
    });

    test('windows proxy when env empty', () {
      expect(
        resolveHttpProxy(
          Uri.parse('https://github.com/x'),
          environment: const {},
          windows: const WindowsProxySettings(
            enabled: true,
            proxyServer: '127.0.0.1:7897',
            proxyOverride: 'localhost;127.*',
          ),
        ),
        'PROXY 127.0.0.1:7897',
      );
    });

    test('windows override forces DIRECT', () {
      expect(
        resolveHttpProxy(
          Uri.parse('http://127.0.0.1/health'),
          environment: const {},
          windows: const WindowsProxySettings(
            enabled: true,
            proxyServer: '127.0.0.1:7897',
            proxyOverride: 'localhost;127.*',
          ),
        ),
        'DIRECT',
      );
    });

    test('disabled windows -> DIRECT', () {
      expect(
        resolveHttpProxy(
          Uri.parse('https://github.com/x'),
          environment: const {},
          windows: const WindowsProxySettings(
            enabled: false,
            proxyServer: '127.0.0.1:7897',
          ),
        ),
        'DIRECT',
      );
    });
  });
}
