import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _solidPng({int w = 2000, int h = 1500}) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(40, 120, 200));
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List _noisyJpg({int w = 2000, int h = 1500}) {
  final image = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      image.setPixelRgb(x, y, (x * 17 + y * 31) & 0xFF, (x * 3) & 0xFF, (y * 5) & 0xFF);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

void main() {
  test('videoDefault 长边压到 ≤1024 且输出 jpeg', () {
    final src = _noisyJpg();
    final out = compressImageBytes(
      src,
      options: ImageCompressOptions.videoDefault,
      fileName: 'ref.png',
    );
    expect(out.mimeType, 'image/jpeg');
    expect(out.fileName, 'ref.jpg');
    expect(out.bytes.length, lessThan(src.length));
    final decoded = img.decodeImage(out.bytes)!;
    final longest =
        decoded.width > decoded.height ? decoded.width : decoded.height;
    expect(longest, lessThanOrEqualTo(1024));
    expect(out.dataUrl, startsWith('data:image/jpeg;base64,'));
  });

  test('videoAggressive 长边压到 ≤768', () {
    final src = _solidPng();
    final out = compressImageBytes(
      src,
      options: ImageCompressOptions.videoAggressive,
      fileName: 'a.webp',
    );
    final decoded = img.decodeImage(out.bytes)!;
    final longest =
        decoded.width > decoded.height ? decoded.width : decoded.height;
    expect(longest, lessThanOrEqualTo(768));
    expect(out.fileName, 'a.jpg');
  });

  test('小 jpeg 且无需缩放时可跳过', () {
    final tiny = img.Image(width: 64, height: 48);
    img.fill(tiny, color: img.ColorRgb8(1, 2, 3));
    final jpg = Uint8List.fromList(img.encodeJpg(tiny, quality: 90));
    final out = compressImageBytes(
      jpg,
      options: const ImageCompressOptions(
        maxEdge: 1280,
        quality: 0.85,
        skipBelowBytes: 1024 * 1024,
      ),
      fileName: 'tiny.jpg',
    );
    expect(out.bytes, same(jpg));
  });

  test('空字节抛错', () {
    expect(
      () => compressImageBytes(Uint8List(0)),
      throwsA(isA<StateError>()),
    );
  });

  test('无法解码抛错', () {
    expect(
      () => compressImageBytes(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8])),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'msg',
        contains('解码'),
      )),
    );
  });
}
