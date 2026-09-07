import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 测试用 minisign 向量（与生产 `kDesktopUpdaterMinisignPubkey` 无关）。
///
/// 用同一套 Ed25519 / Blake2b 库生成，覆盖 Tauri base64 包一层与明文四行格式。
/// 手工 E2E（真实安装包）：见仓库根 `SECURITY.md`「更新包签名」节。
class _TestMinisignVector {
  _TestMinisignVector({
    required this.fileBytes,
    required this.tauriPubkey,
    required this.prehashedSignatureField,
    required this.legacySignatureField,
    required this.plainPrehashedSignatureText,
    required this.badKeyIdSignatureField,
    required this.tamperedGlobalSignatureField,
    required this.badDataSignatureField,
    required this.otherPubkeySameKeyId,
  });

  final List<int> fileBytes;
  final String tauriPubkey;
  final String prehashedSignatureField;
  final String legacySignatureField;
  final String plainPrehashedSignatureText;
  final String badKeyIdSignatureField;
  final String tamperedGlobalSignatureField;
  final String badDataSignatureField;
  final String otherPubkeySameKeyId;

  static Future<_TestMinisignVector> generate() async {
    final algo = Ed25519();
    final keyPair = await algo.newKeyPair();
    final pub = await keyPair.extractPublicKey();
    final keyId = Uint8List.fromList(List<int>.generate(8, (i) => i + 1));

    final pkRecord = BytesBuilder()
      ..add(utf8.encode('Ed'))
      ..add(keyId)
      ..add(pub.bytes);
    final pkText =
        'untrusted comment: minisign public key: TESTKEY01\n'
        '${base64Encode(pkRecord.toBytes())}\n';
    final tauriPubkey = base64Encode(utf8.encode(pkText));

    final fileBytes =
        utf8.encode('ai-studio-flutter-minisign-test-payload-v1');
    const trusted = 'timestamp:1735689600\tfile:test.bin';

    Future<String> buildSignature({
      required bool prehashed,
      Uint8List? overrideKeyId,
      List<int>? overrideDataSig,
      List<int>? overrideGlobalSig,
      bool reSignGlobalForOverrideData = false,
    }) async {
      late final List<int> dataSigBytes;
      if (overrideDataSig != null) {
        dataSigBytes = overrideDataSig;
      } else if (prehashed) {
        final hash = await Blake2b().hash(fileBytes);
        dataSigBytes = (await algo.sign(hash.bytes, keyPair: keyPair)).bytes;
      } else {
        dataSigBytes = (await algo.sign(fileBytes, keyPair: keyPair)).bytes;
      }

      final kid = overrideKeyId ?? keyId;
      final sigRecord = BytesBuilder()
        ..add(utf8.encode(prehashed ? 'ED' : 'Ed'))
        ..add(kid)
        ..add(dataSigBytes);

      late final List<int> globalBytes;
      if (overrideGlobalSig != null) {
        globalBytes = overrideGlobalSig;
      } else {
        final trustedPayload = <int>[
          ...dataSigBytes,
          ...utf8.encode(trusted),
        ];
        // 即使 dataSig 被篡改，也可选择重签 global，使 trusted 校验通过、数据校验失败。
        if (reSignGlobalForOverrideData || overrideDataSig == null) {
          globalBytes =
              (await algo.sign(trustedPayload, keyPair: keyPair)).bytes;
        } else {
          globalBytes =
              (await algo.sign(trustedPayload, keyPair: keyPair)).bytes;
        }
      }

      final text = 'untrusted comment: signature from minisign secret key\n'
          '${base64Encode(sigRecord.toBytes())}\n'
          'trusted comment: $trusted\n'
          '${base64Encode(globalBytes)}\n';
      return text;
    }

    final prehashedPlain = await buildSignature(prehashed: true);
    final legacyPlain = await buildSignature(prehashed: false);

    final badKidPlain = await buildSignature(
      prehashed: true,
      overrideKeyId: Uint8List.fromList(List<int>.filled(8, 9)),
    );

    final goodDataSig = await () async {
      final hash = await Blake2b().hash(fileBytes);
      return (await algo.sign(hash.bytes, keyPair: keyPair)).bytes;
    }();
    final goodGlobal = await () async {
      final trustedPayload = <int>[...goodDataSig, ...utf8.encode(trusted)];
      return (await algo.sign(trustedPayload, keyPair: keyPair)).bytes;
    }();
    final tamperedGlobal = Uint8List.fromList(goodGlobal)..[63] ^= 0xff;
    final tamperedGlobalPlain = await buildSignature(
      prehashed: true,
      overrideDataSig: goodDataSig,
      overrideGlobalSig: tamperedGlobal,
    );

    final badDataSig = Uint8List.fromList(goodDataSig)..[0] ^= 0xff;
    final badDataPlain = await buildSignature(
      prehashed: true,
      overrideDataSig: badDataSig,
      reSignGlobalForOverrideData: true,
    );

    final other = await algo.newKeyPair();
    final otherPub = await other.extractPublicKey();
    final otherPk = BytesBuilder()
      ..add(utf8.encode('Ed'))
      ..add(keyId)
      ..add(otherPub.bytes);
    final otherPkText =
        'untrusted comment: minisign public key: OTHER\n'
        '${base64Encode(otherPk.toBytes())}\n';

    return _TestMinisignVector(
      fileBytes: fileBytes,
      tauriPubkey: tauriPubkey,
      prehashedSignatureField: base64Encode(utf8.encode(prehashedPlain)),
      legacySignatureField: base64Encode(utf8.encode(legacyPlain)),
      plainPrehashedSignatureText: prehashedPlain,
      badKeyIdSignatureField: base64Encode(utf8.encode(badKidPlain)),
      tamperedGlobalSignatureField:
          base64Encode(utf8.encode(tamperedGlobalPlain)),
      badDataSignatureField: base64Encode(utf8.encode(badDataPlain)),
      otherPubkeySameKeyId: base64Encode(utf8.encode(otherPkText)),
    );
  }
}

void main() {
  late _TestMinisignVector v;

  setUpAll(() async {
    v = await _TestMinisignVector.generate();
  });

  group('parseTauriUpdaterPublicKey', () {
    test('parses pinned production pubkey', () {
      final pk = parseTauriUpdaterPublicKey(kDesktopUpdaterMinisignPubkey);
      expect(pk.rawPublicKey.length, 32);
      expect(pk.keyId.length, 8);
      expect(pk.prehashed, isFalse); // 公钥记录算法为 Ed
    });

    test('parses test pubkey', () {
      final pk = parseTauriUpdaterPublicKey(v.tauriPubkey);
      expect(pk.rawPublicKey.length, 32);
      expect(pk.keyId, List<int>.generate(8, (i) => i + 1));
    });

    test('rejects truncated / invalid pubkey', () {
      expect(
        () => parseTauriUpdaterPublicKey(base64Encode(utf8.encode('only-one-line'))),
        throwsA(isA<UpdateException>()),
      );
      expect(
        () => parseTauriUpdaterPublicKey('%%%not-base64%%%'),
        throwsA(isA<UpdateException>()),
      );
    });
  });

  group('parseTauriUpdaterSignature', () {
    test('parses base64-wrapped and plain minisign text', () {
      final wrapped = parseTauriUpdaterSignature(v.prehashedSignatureField);
      expect(wrapped.prehashed, isTrue);
      expect(wrapped.signature.length, 64);
      expect(wrapped.globalSignature.length, 64);
      expect(wrapped.trustedComment, contains('timestamp:'));

      final plain = parseTauriUpdaterSignature(v.plainPrehashedSignatureText);
      expect(plain.prehashed, isTrue);
      expect(plain.keyId, wrapped.keyId);
    });

    test('parses legacy Ed algorithm', () {
      final legacy = parseTauriUpdaterSignature(v.legacySignatureField);
      expect(legacy.prehashed, isFalse);
    });

    test('rejects empty / short / missing trusted comment', () {
      expect(
        () => parseTauriUpdaterSignature(''),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.message,
            'message',
            contains('缺少签名'),
          ),
        ),
      );
      expect(
        () => parseTauriUpdaterSignature(
          base64Encode(utf8.encode('untrusted comment: x\nYWJj\n')),
        ),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.message,
            'message',
            contains('四行'),
          ),
        ),
      );
      final noTrusted = 'untrusted comment: x\n'
          '${base64Encode(List<int>.filled(74, 1))}\n'
          'not trusted comment: y\n'
          '${base64Encode(List<int>.filled(64, 2))}\n';
      expect(
        () => parseTauriUpdaterSignature(base64Encode(utf8.encode(noTrusted))),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.message,
            'message',
            contains('trusted comment'),
          ),
        ),
      );
    });
  });

  group('verifyTauriUpdaterSignature', () {
    test('accepts prehashed ED and legacy Ed vectors', () async {
      await verifyTauriUpdaterSignature(
        fileBytes: v.fileBytes,
        signatureField: v.prehashedSignatureField,
        pubkeyEncoded: v.tauriPubkey,
      );
      await verifyTauriUpdaterSignature(
        fileBytes: v.fileBytes,
        signatureField: v.legacySignatureField,
        pubkeyEncoded: v.tauriPubkey,
      );
      await verifyTauriUpdaterSignature(
        fileBytes: v.fileBytes,
        signatureField: v.plainPrehashedSignatureText,
        pubkeyEncoded: v.tauriPubkey,
      );
    });

    test('fail-closed: empty signature / pubkey / file', () async {
      await expectLater(
        verifyTauriUpdaterSignature(
          fileBytes: v.fileBytes,
          signatureField: '',
          pubkeyEncoded: v.tauriPubkey,
        ),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.message,
            'message',
            contains('缺少签名'),
          ),
        ),
      );
      await expectLater(
        verifyTauriUpdaterSignature(
          fileBytes: v.fileBytes,
          signatureField: v.prehashedSignatureField,
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
      await expectLater(
        verifyTauriUpdaterSignature(
          fileBytes: const [],
          signatureField: v.prehashedSignatureField,
          pubkeyEncoded: v.tauriPubkey,
        ),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.message,
            'message',
            contains('安装包为空'),
          ),
        ),
      );
    });

    test('rejects key id mismatch', () async {
      await expectLater(
        verifyTauriUpdaterSignature(
          fileBytes: v.fileBytes,
          signatureField: v.badKeyIdSignatureField,
          pubkeyEncoded: v.tauriPubkey,
        ),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.message,
            'message',
            contains('密钥与内置公钥不匹配'),
          ),
        ),
      );
    });

    test('rejects tampered trusted comment global sig', () async {
      await expectLater(
        verifyTauriUpdaterSignature(
          fileBytes: v.fileBytes,
          signatureField: v.tamperedGlobalSignatureField,
          pubkeyEncoded: v.tauriPubkey,
        ),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.message,
            'message',
            contains('trusted comment'),
          ),
        ),
      );
    });

    test('rejects bad data signature / wrong pubkey / tampered payload',
        () async {
      await expectLater(
        verifyTauriUpdaterSignature(
          fileBytes: v.fileBytes,
          signatureField: v.badDataSignatureField,
          pubkeyEncoded: v.tauriPubkey,
        ),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.message,
            'message',
            contains('签名校验失败'),
          ),
        ),
      );
      await expectLater(
        verifyTauriUpdaterSignature(
          fileBytes: v.fileBytes,
          signatureField: v.prehashedSignatureField,
          pubkeyEncoded: v.otherPubkeySameKeyId,
        ),
        throwsA(isA<UpdateException>()),
      );
      await expectLater(
        verifyTauriUpdaterSignature(
          fileBytes: utf8.encode('tampered-payload'),
          signatureField: v.prehashedSignatureField,
          pubkeyEncoded: v.tauriPubkey,
        ),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.message,
            'message',
            contains('签名校验失败'),
          ),
        ),
      );
    });
  });

  group('UpdateClient.downloadInstaller signature gate', () {
    test('验签失败删除临时文件并阻断', () async {
      final bytes = List<int>.from(v.fileBytes);
      final mock = MockClient((request) async {
        return http.Response.bytes(bytes, 200, headers: {
          'content-length': '${bytes.length}',
        });
      });
      final dir = await Directory.systemTemp.createTemp('ai_studio_msig_fail_');
      final client = UpdateClient(
        client: mock,
        manifestUrl: 'https://example.com/latest.json',
        downloadDirectory: dir,
        minisignPubkey: v.tauriPubkey,
        requireSignature: true,
      );
      try {
        await expectLater(
          client.downloadInstaller(
            PlatformAsset(
              url: 'https://example.com/setup.exe',
              signature: v.badDataSignatureField,
            ),
          ),
          throwsA(isA<UpdateException>()),
        );
        final leftover = dir.listSync().whereType<File>().toList();
        expect(leftover, isEmpty, reason: '验签失败后临时安装包应已删除');
      } finally {
        client.close();
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    });

    test('缺签名时阻断并清理', () async {
      final bytes = List<int>.from(v.fileBytes);
      final mock = MockClient((request) async {
        return http.Response.bytes(bytes, 200);
      });
      final dir = await Directory.systemTemp.createTemp('ai_studio_msig_nosig_');
      final client = UpdateClient(
        client: mock,
        manifestUrl: 'https://example.com/latest.json',
        downloadDirectory: dir,
        minisignPubkey: v.tauriPubkey,
        requireSignature: true,
      );
      try {
        await expectLater(
          client.downloadInstaller(
            const PlatformAsset(
              url: 'https://example.com/setup.exe',
              signature: '',
            ),
          ),
          throwsA(
            isA<UpdateException>().having(
              (e) => e.message,
              'message',
              contains('缺少签名'),
            ),
          ),
        );
        expect(dir.listSync().whereType<File>(), isEmpty);
      } finally {
        client.close();
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    });

    test('合法签名保留文件', () async {
      final bytes = List<int>.from(v.fileBytes);
      final mock = MockClient((request) async {
        return http.Response.bytes(bytes, 200);
      });
      final dir = await Directory.systemTemp.createTemp('ai_studio_msig_ok_');
      final client = UpdateClient(
        client: mock,
        manifestUrl: 'https://example.com/latest.json',
        downloadDirectory: dir,
        minisignPubkey: v.tauriPubkey,
        requireSignature: true,
      );
      try {
        final file = await client.downloadInstaller(
          PlatformAsset(
            url: 'https://example.com/setup.exe',
            signature: v.prehashedSignatureField,
          ),
        );
        expect(await file.exists(), isTrue);
        expect(await file.readAsBytes(), bytes);
      } finally {
        client.close();
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    });
  });
}
