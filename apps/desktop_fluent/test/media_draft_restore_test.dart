import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:desktop_fluent/pages/image/image_controller.dart';
import 'package:desktop_fluent/pages/video/video_controller.dart';

final png = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
ImageItem imageItem(String prompt, [List<ImageRef> refs = const []]) =>
    ImageItem(
      id: prompt,
      createdAt: 1,
      mode: ImageGenMode.text,
      prompt: prompt,
      n: 9,
      size: 'invalid',
      referenceImages: refs,
    );
VideoItem videoItem(String prompt, [List<ImageRef> refs = const []]) =>
    VideoItem(
      id: prompt,
      createdAt: 1,
      mode: VideoGenMode.text,
      prompt: prompt,
      duration: 999,
      size: 'invalid',
      referenceImages: refs,
    );

void main() {
  for (final video in [false, true]) {
    group(video ? 'video' : 'image', () {
      late ProviderRepository providers;
      late GenerationRuntime generation;
      late dynamic sessions;
      late dynamic controller;
      Future<Uint8List?> Function(ImageRef)? reader;
      setUp(() async {
        providers = ProviderRepository(
          storage: MemoryProviderStorage(),
          connectionTester: StubProviderConnectionTester(),
        );
        await providers.load();
        generation = GenerationRuntime();
        sessions = video
            ? VideoSessionRepository(storage: MemoryVideoSessionStorage())
            : ImageSessionRepository(
                storage: MemoryImageSessionStorage(),
                assetStore: MemoryImageAssetStore(),
              );
        await sessions.load();
        reader = null;
      });
      void create() {
        controller = video
            ? VideoController(
                providerRepository: providers,
                sessionRepository: sessions,
                generation: generation,
                readDraftReference: reader,
              )
            : ImageController(
                providerRepository: providers,
                sessionRepository: sessions,
                generation: generation,
                readDraftReference: reader,
              );
      }

      Future<void> refill(String prompt, [List<ImageRef> refs = const []]) =>
          video
          ? controller.rerunFromItem(videoItem(prompt, refs)) as Future<void>
          : controller.rerunFromItem(imageItem(prompt, refs)) as Future<void>;
      tearDown(() {
        controller.dispose();
        sessions.dispose();
        providers.dispose();
        generation.dispose();
      });
      test(
        'local b64 restores, parameters sanitized, no generation; empty clears',
        () async {
          create();
          await refill(' restored ', [
            ImageRef(type: ImageRefType.b64, src: base64Encode(png)),
          ]);
          expect(controller.promptDraft, 'restored');
          expect(controller.hasReferenceImage, isTrue);
          expect(controller.size, isNot('invalid'));
          expect(generation.busy, isFalse);
          expect(sessions.activeSession.items, isEmpty);
          await refill('empty');
          expect(controller.hasReferenceImage, isFalse);
        },
      );
      test(
        'remote refs skipped and unreadable reference falls back to text',
        () async {
          var reads = 0;
          reader = (_) async {
            reads++;
            return null;
          };
          create();
          await refill('fallback', const [
            ImageRef(type: ImageRefType.url, src: 'https://example.com/a.png'),
          ]);
          expect(reads, 0);
          expect(controller.promptDraft, 'fallback');
          expect(controller.bannerInfo, isNotNull);
        },
      );
      for (final action in [
        'edit',
        'parameter',
        'session',
        'provider',
        'generation',
        'dispose',
        'clear',
      ]) {
        test('late refill rejected after $action', () async {
          final gate = Completer<Uint8List?>();
          reader = (_) => gate.future;
          create();
          controller.setPromptDraft('original');
          final pending = refill('stale', const [
            ImageRef(type: ImageRefType.file, src: 'slow.png'),
          ]);
          switch (action) {
            case 'edit':
              controller.setPromptDraft('manual');
            case 'parameter':
              controller.setSize('manual');
            case 'session':
              await sessions.createSession();
            case 'provider':
              await providers.addProvider(
                name: 'changed',
                baseUrl: 'https://example.com',
                apiKey: 'test',
              );
            case 'generation':
              final token = generation.begin('other', () {});
              generation.end('other', token);
            case 'dispose':
              controller.dispose();
            case 'clear':
              controller.clearReference();
          }
          gate.complete(png);
          await pending;
          expect(
            controller.promptDraft,
            action == 'edit' ? 'manual' : 'original',
          );
          if (action == 'dispose') {
            create();
          }
        });
      }
      test('newer refill wins and busy refill changes nothing', () async {
        final gate = Completer<Uint8List?>();
        reader = (_) => gate.future;
        create();
        final pending = refill('stale', const [
          ImageRef(type: ImageRefType.file, src: 'slow.png'),
        ]);
        await refill('latest');
        gate.complete(png);
        await pending;
        expect(controller.promptDraft, 'latest');
        final token = generation.begin('busy', () {});
        await refill('blocked');
        expect(controller.promptDraft, 'latest');
        generation.end('busy', token);
      });
    });
  }
}
