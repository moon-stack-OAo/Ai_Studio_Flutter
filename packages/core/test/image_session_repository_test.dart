import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ImageSessionRepository repo;
  late MemoryImageSessionStorage storage;
  late MemoryImageAssetStore assets;

  setUp(() async {
    storage = MemoryImageSessionStorage();
    assets = MemoryImageAssetStore();
    repo = ImageSessionRepository(storage: storage, assetStore: assets);
    await repo.load();
  });

  test('load 空存储创建默认会话', () {
    expect(repo.sessions.length, 1);
    expect(repo.activeId, isNotEmpty);
    expect(repo.activeSession?.title, '新生图');
  });

  test('create / setActive / remove', () async {
    final a = repo.activeSession!;
    final b = await repo.createSession(title: '第二');
    expect(repo.activeId, b.id);
    expect(repo.sessions.length, 2);

    await repo.setActive(a.id);
    expect(repo.activeId, a.id);

    await repo.removeSession(b.id);
    expect(repo.sessions.any((s) => s.id == b.id), isFalse);
    expect(repo.sessions, isNotEmpty);
  });

  test('appendLoading 截 title + complete 落盘 file', () async {
    final sid = repo.activeId;
    final item = await repo.appendLoadingItem(
      sid,
      mode: ImageGenMode.text,
      prompt: '这是一段超过二十四字的生图提示词用来截断标题测试啊',
      model: 'gpt-image-1',
      providerName: 'OpenAI',
      n: 1,
      size: '1024x1024',
    );
    expect(item, isNotNull);
    expect(repo.activeSession!.title.length, 24);
    expect(item!.status, ImageItemStatus.loading);

    final pngBytes = Uint8List.fromList(base64Decode(
      // 1x1 PNG
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    ));
    final b64 = base64Encode(pngBytes);
    await repo.completeItem(sid, item.id, [
      ImageRef(type: ImageRefType.b64, src: b64),
    ]);
    final done = repo.activeSession!.items.last;
    expect(done.status, ImageItemStatus.done);
    expect(done.images.single.type, ImageRefType.file);
    expect(done.images.single.src, startsWith('memory://'));
    final read = await repo.readImageBytes(done.images.single);
    expect(read, isNotNull);
    expect(read!.length, pngBytes.length);
  });

  test('failItem 与 hydrate loading→error', () async {
    final sid = repo.activeId;
    final item = await repo.appendLoadingItem(
      sid,
      mode: ImageGenMode.text,
      prompt: 'fail me',
    );
    await repo.failItem(sid, item!.id, '已取消');
    expect(repo.activeSession!.items.last.status, ImageItemStatus.error);
    expect(repo.activeSession!.items.last.errorMessage, '已取消');

    // 手动写入残留 loading，再 load
    final dirty = ImageSession(
      id: 'img_dirty',
      title: '脏',
      createdAt: 1,
      updatedAt: 2,
      items: [
        ImageItem(
          id: 'imgi_x',
          createdAt: 1,
          mode: ImageGenMode.text,
          prompt: 'x',
          status: ImageItemStatus.loading,
        ),
      ],
    );
    await storage.save(
      ImageStoreSnapshot(sessions: [dirty], activeId: dirty.id),
    );
    final b = ImageSessionRepository(storage: storage, assetStore: assets);
    await b.load();
    expect(b.activeSession!.items.single.status, ImageItemStatus.error);
    expect(b.activeSession!.items.single.errorMessage, '上次异常中断');
  });

  test('Memory 持久化 roundtrip', () async {
    final sid = repo.activeId;
    final item = await repo.appendLoadingItem(
      sid,
      mode: ImageGenMode.text,
      prompt: '持久化',
      n: 2,
    );
    await repo.completeItem(sid, item!.id, [
      const ImageRef(
        type: ImageRefType.url,
        src: 'https://example.com/a.png',
      ),
    ]);

    final b = ImageSessionRepository(storage: storage, assetStore: assets);
    await b.load();
    expect(b.activeId, sid);
    expect(b.activeSession!.items.length, 1);
    expect(b.activeSession!.items.first.prompt, '持久化');
    expect(b.activeSession!.items.first.status, ImageItemStatus.done);
  });
}
