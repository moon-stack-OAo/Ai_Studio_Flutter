import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('assertSafeFetchUrl', () {
    test('allows relative blob data and public https', () {
      expect(() => assertSafeFetchUrl('/api/chat'), returnsNormally);
      expect(() => assertSafeFetchUrl('blob:http://localhost/abc'), returnsNormally);
      expect(() => assertSafeFetchUrl('data:text/plain,hello'), returnsNormally);
      expect(
        () => assertSafeFetchUrl('https://api.openai.com/v1/chat'),
        returnsNormally,
      );
      expect(() => assertSafeFetchUrl('http://127.0.0.1:8080/'), returnsNormally);
      expect(() => assertSafeFetchUrl('http://localhost:3000/v1'), returnsNormally);
      expect(
        () => assertSafeFetchUrl('http://192.168.1.10:8080/v1'),
        returnsNormally,
      );
    });

    test('blocks dangerous schemes', () {
      expect(
        () => assertSafeFetchUrl('file:///etc/passwd'),
        throwsA(isA<UrlSafetyException>()),
      );
      expect(
        () => assertSafeFetchUrl('ftp://example.com/file'),
        throwsA(isA<UrlSafetyException>()),
      );
    });

    test('blocks metadata and link-local', () {
      expect(
        () => assertSafeFetchUrl('http://169.254.169.254/latest/meta-data/'),
        throwsA(isA<UrlSafetyException>()),
      );
      expect(
        () => assertSafeFetchUrl('http://169.254.1.1/'),
        throwsA(isA<UrlSafetyException>()),
      );
      expect(
        () => assertSafeFetchUrl('http://metadata.google.internal/'),
        throwsA(isA<UrlSafetyException>()),
      );
      expect(
        () => assertSafeFetchUrl('http://kubernetes.default.svc/'),
        throwsA(isA<UrlSafetyException>()),
      );
      expect(
        () => assertSafeFetchUrl('http://0.0.0.0/'),
        throwsA(isA<UrlSafetyException>()),
      );
      expect(
        () => assertSafeFetchUrl('http://[::1]/'),
        throwsA(isA<UrlSafetyException>()),
      );
      expect(
        () => assertSafeFetchUrl('http://[fd00:ec2::254]/'),
        throwsA(isA<UrlSafetyException>()),
      );
      expect(
        () => assertSafeFetchUrl('http://[::ffff:169.254.169.254]/'),
        throwsA(isA<UrlSafetyException>()),
      );
    });
  });

  group('warnUnsafeUrl', () {
    test('null for public https', () {
      expect(warnUnsafeUrl('https://api.openai.com/v1'), isNull);
    });

    test('warns http loopback private', () {
      expect(warnUnsafeUrl('http://api.example.com/v1'), contains('明文 HTTP'));
      expect(warnUnsafeUrl('http://127.0.0.1:8080/v1'), contains('本机'));
      expect(warnUnsafeUrl('https://10.0.0.5/v1'), contains('私有网段'));
    });
  });

  group('minisign pubkey parse', () {
    test('parses pinned Tauri pubkey', () {
      final pk = parseTauriUpdaterPublicKey(kDesktopUpdaterMinisignPubkey);
      expect(pk.rawPublicKey.length, 32);
      expect(pk.keyId.length, 8);
    });

    test('fail-closed when signature empty', () async {
      await expectLater(
        verifyTauriUpdaterSignature(
          fileBytes: [1, 2, 3],
          signatureField: '',
        ),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.message,
            'message',
            contains('缺少签名'),
          ),
        ),
      );
    });

    test('fail-closed when pubkey empty', () async {
      await expectLater(
        verifyTauriUpdaterSignature(
          fileBytes: [1, 2, 3],
          signatureField: 'dGVzdA==',
          pubkeyEncoded: '',
        ),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.message,
            'message',
            contains('未配置更新验签公钥'),
          ),
        ),
      );
    });
  });
}
