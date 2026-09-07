import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'update_client.dart';

/// 现网 Tauri updater 公钥（`AI_Studio/src-tauri/tauri.conf.json` → `plugins.updater.pubkey`）。
///
/// 值为 base64(UTF-8 minisign 公钥文本)；解码后第二行即 `RW…` 公钥记录。
const String kDesktopUpdaterMinisignPubkey =
    'dW50cnVzdGVkIGNvbW1lbnQ6IG1pbmlzaWduIHB1YmxpYyBrZXk6IDZGMUJCRjQyMzU3NkQ1QgpSV1JiYlZjajlMdnhCalBHQ3hHUldFdTFuSDdiMHkySW9wb0c0MGF6L0xtaEJxaHlVdzNEYTRiQgo=';

const String _trustedCommentPrefix = 'trusted comment: ';

/// Tauri / minisign 公钥解析结果。
class MinisignPublicKey {
  const MinisignPublicKey({
    required this.keyId,
    required this.rawPublicKey,
    required this.prehashed,
  });

  final Uint8List keyId;
  final Uint8List rawPublicKey;
  final bool prehashed;
}

/// Tauri updater `.sig`（清单 `signature` 字段，多为 base64 包一层）解析结果。
class MinisignSignature {
  const MinisignSignature({
    required this.prehashed,
    required this.keyId,
    required this.signature,
    required this.trustedComment,
    required this.globalSignature,
  });

  final bool prehashed;
  final Uint8List keyId;
  final Uint8List signature;
  final String trustedComment;
  final Uint8List globalSignature;
}

bool _listEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Uint8List _decodeBase64Strict(String raw, String label) {
  final cleaned = raw.replaceAll(RegExp(r'\s'), '');
  try {
    return Uint8List.fromList(base64Decode(cleaned));
  } catch (e) {
    throw UpdateException('$label Base64 无效：$e');
  }
}

bool _parseAlgorithm(List<int> bytes, String label) {
  if (bytes.length < 2) {
    throw UpdateException('$label 算法字段过短');
  }
  final algo = String.fromCharCodes(bytes.sublist(0, 2));
  if (algo == 'ED') return true; // prehashed (BLAKE2b-512)
  if (algo == 'Ed') return false; // legacy raw
  throw UpdateException('$label 不支持的 minisign 算法：$algo');
}

/// 解析 Tauri 配置中的 updater pubkey（整段 base64）。
MinisignPublicKey parseTauriUpdaterPublicKey(String encodedPublicKey) {
  final text = utf8.decode(_decodeBase64Strict(encodedPublicKey, '更新公钥'));
  final lines = text.replaceAll('\r\n', '\n').split('\n')
    ..removeWhere((l) => l.isEmpty);
  if (lines.length < 2) {
    throw const UpdateException('更新公钥格式无效（期望 minisign 两行文本）');
  }
  final keyRecord = _decodeBase64Strict(lines[1], 'minisign 公钥记录');
  if (keyRecord.length != 42) {
    throw UpdateException(
      'minisign 公钥记录长度应为 42，实际 ${keyRecord.length}',
    );
  }
  final prehashed = _parseAlgorithm(keyRecord, 'minisign 公钥');
  return MinisignPublicKey(
    keyId: Uint8List.fromList(keyRecord.sublist(2, 10)),
    rawPublicKey: Uint8List.fromList(keyRecord.sublist(10)),
    prehashed: prehashed,
  );
}

/// 解析清单 `signature` 字段（Tauri：多为 base64(minisign 文本)）。
MinisignSignature parseTauriUpdaterSignature(String encodedSignature) {
  final trimmed = encodedSignature.trim();
  if (trimmed.isEmpty) {
    throw const UpdateException('更新包缺少签名');
  }

  String signatureText;
  try {
    signatureText = utf8.decode(_decodeBase64Strict(trimmed, '更新签名'));
  } catch (_) {
    // 兼容已是明文 minisign 文本的情况
    if (trimmed.contains('untrusted comment:') ||
        trimmed.contains(_trustedCommentPrefix)) {
      signatureText = trimmed;
    } else {
      rethrow;
    }
  }

  final lines = signatureText.replaceAll('\r\n', '\n').split('\n')
    ..removeWhere((l) => l.trim().isEmpty);
  if (lines.length < 4) {
    throw const UpdateException('更新签名格式无效（期望 minisign 四行）');
  }

  // lines: [untrusted comment, sig record, trusted comment, global sig]
  final sigRecordLine = lines[1];
  final trustedLine = lines[2];
  final globalLine = lines[3];

  if (!trustedLine.startsWith(_trustedCommentPrefix)) {
    throw const UpdateException('更新签名缺少 trusted comment');
  }

  final signatureRecord = _decodeBase64Strict(sigRecordLine, 'minisign 签名记录');
  if (signatureRecord.length != 74) {
    throw UpdateException(
      'minisign 签名记录长度应为 74，实际 ${signatureRecord.length}',
    );
  }
  final globalSignature = _decodeBase64Strict(globalLine, 'minisign 全局签名');
  if (globalSignature.length != 64) {
    throw UpdateException(
      'minisign 全局签名长度应为 64，实际 ${globalSignature.length}',
    );
  }

  return MinisignSignature(
    prehashed: _parseAlgorithm(signatureRecord, 'minisign 签名'),
    keyId: Uint8List.fromList(signatureRecord.sublist(2, 10)),
    signature: Uint8List.fromList(signatureRecord.sublist(10)),
    trustedComment: trustedLine.substring(_trustedCommentPrefix.length),
    globalSignature: globalSignature,
  );
}

Future<List<int>> _payloadForVerification(
  List<int> fileBytes,
  bool prehashed,
) async {
  if (!prehashed) return fileBytes;
  final hash = await Blake2b().hash(fileBytes);
  return hash.bytes;
}

Future<bool> _ed25519Verify({
  required List<int> message,
  required List<int> signatureBytes,
  required List<int> publicKeyBytes,
}) async {
  final algorithm = Ed25519();
  final publicKey = SimplePublicKey(
    publicKeyBytes,
    type: KeyPairType.ed25519,
  );
  return algorithm.verify(
    message,
    signature: Signature(signatureBytes, publicKey: publicKey),
  );
}

/// 用钉死公钥校验安装包字节与清单 signature（失败抛 [UpdateException]）。
///
/// 失败安全：
/// - [signatureField] 为空 → 阻断
/// - [pubkeyEncoded] 为空 → 阻断（禁止静默跳过）
/// - 验签失败 / 格式错误 → 阻断
Future<void> verifyTauriUpdaterSignature({
  required List<int> fileBytes,
  required String signatureField,
  String pubkeyEncoded = kDesktopUpdaterMinisignPubkey,
}) async {
  final pubkey = pubkeyEncoded.trim();
  if (pubkey.isEmpty) {
    throw const UpdateException(
      '未配置更新验签公钥，已阻断安装（失败安全）',
    );
  }
  final sigRaw = signatureField.trim();
  if (sigRaw.isEmpty) {
    throw const UpdateException('更新清单缺少签名，已阻断安装');
  }
  if (fileBytes.isEmpty) {
    throw const UpdateException('安装包为空，无法验签');
  }

  final publicKey = parseTauriUpdaterPublicKey(pubkey);
  final signature = parseTauriUpdaterSignature(sigRaw);

  if (!_listEquals(publicKey.keyId, signature.keyId)) {
    throw const UpdateException('更新签名密钥与内置公钥不匹配');
  }

  final trustedPayload = <int>[
    ...signature.signature,
    ...utf8.encode(signature.trustedComment),
  ];
  final trustedOk = await _ed25519Verify(
    message: trustedPayload,
    signatureBytes: signature.globalSignature,
    publicKeyBytes: publicKey.rawPublicKey,
  );
  if (!trustedOk) {
    throw const UpdateException('更新签名 trusted comment 校验失败');
  }

  final payload = await _payloadForVerification(fileBytes, signature.prehashed);
  final dataOk = await _ed25519Verify(
    message: payload,
    signatureBytes: signature.signature,
    publicKeyBytes: publicKey.rawPublicKey,
  );
  if (!dataOk) {
    throw const UpdateException('更新包签名校验失败，已阻断安装');
  }
}
