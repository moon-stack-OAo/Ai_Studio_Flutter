import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubExtractor implements VideoFrameExtractor {
  _StubExtractor(this.bytes);
  final Uint8List? bytes;
  String? lastPath;

  @override
  Future<Uint8List?> extractJpeg(
    String videoPath, {
    Duration at = const Duration(milliseconds: 400),
  }) async {
    lastPath = videoPath;
    return bytes;
  }
}

void main() {
  test('MemoryVideoPosterStore save/path/clear', () async {
    final store = MemoryVideoPosterStore();
    expect(await store.pathFor('a'), isNull);
    final path = await store.saveJpeg(Uint8List.fromList([1, 2, 3]), 'a');
    expect(path, 'memory-poster://a');
    expect(await store.pathFor('a'), path);
    expect(await store.estimateBytes(), 3);
    await store.clearAll();
    expect(await store.pathFor('a'), isNull);
  });

  test('peekPoster prefers remote posterUrl', () {
    final service = VideoPosterService(store: MemoryVideoPosterStore());
    final item = VideoItem(
      id: '1',
      createdAt: 1,
      mode: VideoGenMode.text,
      prompt: 'p',
      status: VideoItemStatus.success,
      posterUrl: 'https://cdn.example.com/p.jpg',
      posterLocalPath: 'memory-poster://1',
    );
    expect(service.peekPoster(item), 'https://cdn.example.com/p.jpg');
  });

  test('isRemotePosterUrl rejects blocked hosts', () {
    expect(
      VideoPosterService.isRemotePosterUrl('https://169.254.169.254/x'),
      isFalse,
    );
    expect(
      VideoPosterService.isRemotePosterUrl('https://cdn.example.com/p.jpg'),
      isTrue,
    );
  });

  test('VideoItem poster fields round-trip JSON', () {
    final item = VideoItem(
      id: 'v1',
      createdAt: 10,
      mode: VideoGenMode.text,
      prompt: 'hi',
      status: VideoItemStatus.success,
      posterUrl: 'https://cdn.example.com/a.jpg',
      posterLocalPath: '/tmp/a.jpg',
    );
    final back = VideoItem.fromJson(item.toJson());
    expect(back.posterUrl, item.posterUrl);
    expect(back.posterLocalPath, item.posterLocalPath);
  });

  test('fromJson accepts thumbnailUrl alias', () {
    final back = VideoItem.fromJson({
      'id': 'v1',
      'createdAt': 1,
      'mode': 'text',
      'prompt': 'p',
      'status': 'success',
      'thumbnailUrl': 'https://cdn.example.com/t.jpg',
    });
    expect(back.posterUrl, 'https://cdn.example.com/t.jpg');
  });

  test('extractVideoPosterUrl reads nested poster', () {
    final url = extractVideoPosterUrl({
      'data': {
        'video': {'poster_url': 'https://cdn.example.com/poster.jpg'},
      },
    });
    expect(url, 'https://cdn.example.com/poster.jpg');
  });

  test('ensureLocalPoster uses extractor when no remote poster', () async {
    final store = MemoryVideoPosterStore();
    final extractor = _StubExtractor(Uint8List.fromList([9, 9]));
    final service = VideoPosterService(store: store, extractor: extractor);
    // 无本地文件时不抽帧
    final item = VideoItem(
      id: 'x',
      createdAt: 1,
      mode: VideoGenMode.text,
      prompt: 'p',
      status: VideoItemStatus.success,
      localPath: 'C:\\missing\\nope.mp4',
    );
    expect(await service.ensureLocalPoster(item), isNull);
  });
}
