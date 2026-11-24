import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ImageStorage extends MemoryImageSessionStorage {
  bool fail = false;
  bool failLoad = false;
  int saves = 0;
  Completer<void>? gate;
  @override
  Future<ImageStoreSnapshot> load() async {
    if (failLoad) throw const HistoryStorageException();
    return super.load();
  }

  @override
  Future<void> save(ImageStoreSnapshot snapshot) async {
    saves++;
    if (fail) throw StateError('write failed');
    if (gate != null) await gate!.future;
    await super.save(snapshot);
  }
}

class _ChatStorage extends MemoryChatSessionStorage {
  bool fail = false;
  int saves = 0;
  @override
  Future<void> save(ChatStoreSnapshot snapshot) async {
    saves++;
    if (fail) throw StateError('write failed');
    await super.save(snapshot);
  }
}

class _VideoStorage extends MemoryVideoSessionStorage {
  bool fail = false;
  int saves = 0;
  @override
  Future<void> save(VideoStoreSnapshot snapshot) async {
    saves++;
    if (fail) throw StateError('write failed');
    await super.save(snapshot);
  }
}

class _CountingImages extends MemoryImageAssetStore {
  int deletions = 0;
  @override
  Future<void> delete(String pathOrId) async {
    deletions++;
    await super.delete(pathOrId);
  }

  @override
  Future<void> clearAll() async {
    deletions++;
    await super.clearAll();
  }

  @override
  Future<void> clearExcept(Set<String> retained) async {
    deletions++;
    await super.clearExcept(retained);
  }
}

class _CountingVideos extends MemoryVideoAssetStore {
  int deletions = 0;
  @override
  Future<void> delete(String pathOrId) async {
    deletions++;
    await super.delete(pathOrId);
  }

  @override
  Future<void> clearAll() async {
    deletions++;
    await super.clearAll();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final bytes = Uint8List.fromList([1, 2, 3]);
  for (final kind in ['image', 'chat', 'video']) {
    test(
      '$kind fallback clear persists empty before deleting assets',
      () async {
        final assets = MemoryImageAssetStore();
        final videos = MemoryVideoAssetStore();
        final dynamic storage = switch (kind) {
          'chat' => _ChatStorage(),
          'video' => _VideoStorage(),
          _ => _ImageStorage(),
        };
        final dynamic repo = switch (kind) {
          'chat' => ChatSessionRepository(
            storage: storage,
            attachmentStore: assets,
          ),
          'video' => VideoSessionRepository(
            storage: storage,
            assetStore: videos,
            referenceImageStore: assets,
          ),
          _ => ImageSessionRepository(storage: storage, assetStore: assets),
        };
        await repo.load();
        final path = await assets.savePng(bytes, 'shared');
        final ref = ImageRef(type: ImageRefType.file, src: path);
        if (kind == 'chat') {
          await repo.appendMessage(
            repo.activeId,
            role: ChatRole.user,
            content: '',
            attachments: [ref],
          );
        } else {
          await repo.appendLoadingItem(
            repo.activeId,
            mode: kind == 'video' ? VideoGenMode.text : ImageGenMode.text,
            prompt: 'test',
            referenceImages: [ref],
          );
        }
        final before = storage.saves;
        await repo.setActive(repo.activeId);
        expect(storage.saves, before, reason: 'same active id must not write');
        storage.fail = true;
        await expectLater(repo.clearAllSessions(), throwsStateError);
        expect(await assets.read(path), bytes);
        expect((await storage.load()).sessions.first.id, repo.activeId);
        storage.fail = false;
        await repo.clearAllSessions();
        expect(await assets.read(path), isNull);
        expect((await storage.load()).sessions.single.id, repo.activeId);
        repo.dispose();
      },
    );
  }

  test('shared image/video/chat references protect only live assets', () async {
    final guard = AssetReferenceGuard();
    final assets = MemoryImageAssetStore();
    final images = ImageSessionRepository(
      storage: MemoryImageSessionStorage(),
      assetStore: assets,
      assetReferences: guard,
    );
    final videos = VideoSessionRepository(
      storage: MemoryVideoSessionStorage(),
      referenceImageStore: assets,
      assetReferences: guard,
    );
    final chat = ChatSessionRepository(
      storage: MemoryChatSessionStorage(),
      attachmentStore: assets,
      assetReferences: guard,
    );
    await images.load();
    await videos.load();
    await chat.load();
    final path = await assets.savePng(bytes, 'shared');
    final orphan = await assets.savePng(bytes, 'orphan');
    final ref = ImageRef(type: ImageRefType.file, src: path);
    await images.appendLoadingItem(
      images.activeId,
      mode: ImageGenMode.text,
      prompt: 'i',
      referenceImages: [ref],
    );
    await videos.appendLoadingItem(
      videos.activeId,
      mode: VideoGenMode.text,
      prompt: 'v',
      referenceImages: [ref],
    );
    await chat.appendMessage(
      chat.activeId,
      role: ChatRole.user,
      content: 'c',
      attachments: [ref],
    );
    await images.clearAllSessions();
    expect(await assets.read(path), bytes);
    expect(await assets.read(orphan), isNull);
    await videos.clearItems(videos.activeId);
    expect(await assets.read(path), bytes);
    await chat.clearAllSessions();
    expect(await assets.read(path), isNull);
    images.dispose();
    videos.dispose();
    chat.dispose();
  });

  test(
    'unloaded peer blocks destructive cleanup before history changes',
    () async {
      final guard = AssetReferenceGuard();
      final assets = MemoryImageAssetStore();
      final images = ImageSessionRepository(
        storage: MemoryImageSessionStorage(),
        assetStore: assets,
        assetReferences: guard,
      );
      final peer = VideoSessionRepository(
        storage: MemoryVideoSessionStorage(),
        referenceImageStore: assets,
        assetReferences: guard,
      );
      await images.load();
      final id = images.activeId;
      await expectLater(
        images.removeSession(id),
        throwsA(isA<HistoryStorageException>()),
      );
      expect(images.activeId, id);
      await expectLater(
        images.clearAllSessions(),
        throwsA(isA<HistoryStorageException>()),
      );
      await peer.load();
      await images.clearAllSessions();
      images.dispose();
      peer.dispose();
    },
  );

  test('same active id does not bypass busy safety', () async {
    final storage = _ImageStorage();
    final repo = ImageSessionRepository(storage: storage);
    await repo.load();
    storage.gate = Completer<void>();
    final clear = repo.clearAllSessions();
    await expectLater(
      repo.setActive(repo.activeId),
      throwsA(isA<HistoryStorageException>()),
    );
    storage.gate!.complete();
    await clear;
    repo.dispose();
  });

  for (final mediaCache in [false, true]) {
    for (final failSecond in [false, true]) {
      test(
        'global clear media=$mediaCache fails=$failSecond before asset cleanup',
        () async {
          final guard = AssetReferenceGuard();
          final assets = _CountingImages();
          final videoAssets = _CountingVideos();
          final storage = _ImageStorage();
          final chat = ChatSessionRepository(
            storage: MemoryChatSessionStorage(),
            attachmentStore: assets,
            assetReferences: guard,
          );
          final images = ImageSessionRepository(
            storage: storage,
            assetStore: assets,
            assetReferences: guard,
          );
          final videos = VideoSessionRepository(
            storage: MemoryVideoSessionStorage(),
            assetStore: videoAssets,
            referenceImageStore: assets,
            assetReferences: guard,
          );
          storage.failLoad = !failSecond;
          await chat.load();
          await images.load();
          await videos.load();
          expect(images.lastError != null, !failSecond);
          final path = await assets.savePng(bytes, 'keep');
          final videoPath = await videoAssets.saveMp4(bytes, 'keep');
          final posters = MemoryVideoPosterStore();
          final item = await videos.appendLoadingItem(
            videos.activeId,
            prompt: 'poster',
            model: 'm',
            mode: VideoGenMode.text,
          );
          final poster = await posters.saveJpeg(bytes, item!.id);
          await videos.updateItem(
            videos.activeId,
            item.id,
            localPath: videoPath,
            posterLocalPath: poster,
          );
          await chat.appendMessage(
            chat.activeId,
            role: ChatRole.user,
            content: '',
            attachments: [ImageRef(type: ImageRefType.file, src: path)],
          );
          final service = DataBackupService(
            providers: ProviderRepository(
              storage: MemoryProviderStorage(),
              connectionTester: StubProviderConnectionTester(),
            ),
            appearance: AppearanceRepository(
              storage: MemoryAppearanceStorage(),
            ),
            chatDefaults: ChatDefaultsRepository(
              storage: MemoryChatDefaultsStorage(),
            ),
            chatSessions: chat,
            imageSessions: images,
            videoSessions: videos,
            videoPosterStore: posters,
          );
          storage.fail = failSecond;
          final clear = service.clearLocalData(
            ClearLocalDataFlags(sessions: true, mediaCache: mediaCache),
          );
          if (failSecond) {
            await expectLater(clear, throwsStateError);
            expect(assets.deletions, 0);
            expect(videoAssets.deletions, 0);
            expect(await assets.read(path), bytes);
            expect(await videoAssets.read(videoPath), bytes);
            expect(await posters.pathFor(item.id), poster);
          } else {
            await clear;
            expect(images.lastError, isNull);
            expect(images.isLoaded, isTrue);
            // Explicit clear makes this formerly unreadable peer safe again.
            await chat.removeSession(chat.activeId);
            expect(await assets.read(path), isNull);
            expect(await videoAssets.read(videoPath), isNull);
            expect(await posters.pathFor(item.id), isNull);
          }
          chat.dispose();
          images.dispose();
          videos.dispose();
        },
      );
    }
  }

  test(
    'poster deletion refuses linked files and external directories',
    () async {
      final temp = await Directory.systemTemp.createTemp('poster-safety-');
      try {
        final root = await Directory('${temp.path}/cache').create();
        final external = await File(
          '${temp.path}/outside.jpg',
        ).writeAsBytes(bytes);
        final store = FileVideoPosterStore(overrideDir: root);
        final path = await store.saveJpeg(bytes, 'w');
        await File(path).delete();
        try {
          await Link(path).create(external.path);
          await store.delete('w');
          await store.clearAll();
          expect(await external.readAsBytes(), bytes);
          expect(
            await FileSystemEntity.type(path, followLinks: false),
            FileSystemEntityType.link,
          );
        } on FileSystemException catch (error) {
          if (error.osError?.errorCode != 1314) rethrow;
        }
      } finally {
        await temp.delete(recursive: true);
      }
    },
  );

  for (final kind in ['image', 'video']) {
    test('$kind file deletion refuses external and traversal paths', () async {
      final temp = await Directory.systemTemp.createTemp('asset-safety-');
      try {
        final root = await Directory('${temp.path}/cache').create();
        final external = await File(
          '${temp.path}/outside.bin',
        ).writeAsBytes(bytes);
        final dynamic store = kind == 'image'
            ? FileImageAssetStore(overrideDir: root)
            : FileVideoAssetStore(overrideDir: root);
        final String path = kind == 'image'
            ? await store.savePng(bytes, 'w')
            : await store.saveMp4(bytes, 'w');
        await store.delete(external.path);
        await store.delete('${root.path}/../outside.bin');
        expect(await external.exists(), isTrue);
        expect(
          await store.read(external.path),
          bytes,
          reason: 'external reads unchanged',
        );
        final link = Link('${root.path}/outside-link');
        try {
          await link.create(external.path);
          await store.delete(link.path);
          await store.clearAll();
          expect(await external.exists(), isTrue);
          expect(
            await FileSystemEntity.type(link.path, followLinks: false),
            FileSystemEntityType.link,
          );
        } on FileSystemException catch (error) {
          // Windows without link privilege cannot exercise this platform case.
          if (error.osError?.errorCode != 1314) rethrow;
        }
        await store.delete(path);
        expect(await File(path).exists(), isFalse);
        final nested = await Directory('${root.path}/nested').create();
        await File('${nested.path}/asset').writeAsBytes(bytes);
        await store.clearAll();
        expect(await File('${nested.path}/asset').exists(), isFalse);
        expect(await external.exists(), isTrue);
      } finally {
        await temp.delete(recursive: true);
      }
    });
  }
}
