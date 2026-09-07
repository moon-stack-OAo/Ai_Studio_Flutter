import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'update_client.dart';

/// 规范化 sha256 十六进制串（去空白、转小写）。
String normalizeSha256(String? value) =>
    (value ?? '').trim().toLowerCase();

/// 是否为合法 64 位 hex sha256。
bool isValidSha256(String? value) {
  final hex = normalizeSha256(value);
  return hex.length == 64 && RegExp(r'^[0-9a-f]+$').hasMatch(hex);
}

/// 要求清单提供合法 sha256；否则抛 [UpdateException]。
String requireValidSha256(String? value) {
  final hex = normalizeSha256(value);
  if (!isValidSha256(hex)) {
    throw const UpdateException('更新清单缺少完整性校验信息');
  }
  return hex;
}

/// 计算字节的 sha256 hex。
String sha256HexOfBytes(List<int> bytes) =>
    sha256.convert(bytes).toString();

/// 计算字符串 UTF-8 的 sha256 hex（测试便利）。
String sha256HexOfUtf8(String text) =>
    sha256HexOfBytes(utf8.encode(text));

/// 流式计算文件 sha256；可选 [onProgress]。
Future<String> sha256HexOfFile(
  File file, {
  void Function(int readBytes)? onProgress,
}) async {
  if (!await file.exists()) {
    throw UpdateException('校验失败：文件不存在 ${file.path}');
  }
  final output = _DigestCollector();
  final sink = sha256.startChunkedConversion(output);
  await for (final chunk in file.openRead()) {
    onProgress?.call(chunk.length);
    sink.add(chunk);
  }
  sink.close();
  final digest = output.value;
  if (digest == null) {
    throw const UpdateException('校验失败：无法计算 sha256');
  }
  return digest.toString();
}

class _DigestCollector implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// 校验文件 sha256；不匹配则删除文件并抛错。
Future<void> verifyFileSha256(
  File file,
  String expectedSha256, {
  bool deleteOnMismatch = true,
}) async {
  final expected = requireValidSha256(expectedSha256);
  final actual = await sha256HexOfFile(file);
  if (actual != expected) {
    if (deleteOnMismatch) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    throw const UpdateException('安装包完整性校验失败（sha256 不匹配）');
  }
}

/// 校验内存字节（测试 / 小文件）。
void verifyBytesSha256(Uint8List bytes, String expectedSha256) {
  final expected = requireValidSha256(expectedSha256);
  final actual = sha256HexOfBytes(bytes);
  if (actual != expected) {
    throw const UpdateException('安装包完整性校验失败（sha256 不匹配）');
  }
}
