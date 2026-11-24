import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final png = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
  test('local files readable/missing/bad and b64 MIME/size bounds', () async {
    final dir = await Directory.systemTemp.createTemp('media_restore');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/image.png');
    await file.writeAsBytes(png);
    Future<MediaDraftReference?> select(List<ImageRef> refs) =>
        selectMediaDraftReference(refs, isCurrent: () => true);
    expect(
      await select([ImageRef(type: ImageRefType.file, src: file.path)]),
      isNotNull,
    );
    await file.writeAsString('not an image');
    expect(
      await select([ImageRef(type: ImageRefType.file, src: file.path)]),
      isNull,
    );
    await file.delete();
    expect(
      await select([ImageRef(type: ImageRefType.file, src: file.path)]),
      isNull,
    );
    expect(
      await select([ImageRef(type: ImageRefType.b64, src: base64Encode(png))]),
      isNotNull,
    );
    for (final src in [
      'invalid',
      'data:text/html;base64,${base64Encode(png)}',
      'a' * (maxImageB64SrcChars + 1),
    ]) {
      expect(
        await select([ImageRef(type: ImageRefType.b64, src: src)]),
        isNull,
      );
    }
  });
  test('remote refs never read, failed local candidates skipped', () async {
    var reads = 0;
    final ref = await selectMediaDraftReference(
      const [
        ImageRef(type: ImageRefType.url, src: 'http://169.254.169.254/a'),
        ImageRef(type: ImageRefType.file, src: 'missing'),
        ImageRef(type: ImageRefType.file, src: 'good'),
      ],
      isCurrent: () => true,
      read: (ref) async {
        reads++;
        if (ref.src == 'missing') throw StateError('missing');
        return png;
      },
    );
    expect(reads, 2);
    expect(ref!.ref.src, 'good');
  });
  test(
    'guard rejects delayed completion even after source changes back',
    () async {
      final source = ChangeNotifier();
      final guard = MediaDraftRestoreGuard([source]);
      final gate = Completer<Uint8List?>();
      final ticket = guard.begin();
      final pending = selectMediaDraftReference(
        const [ImageRef(type: ImageRefType.file, src: 'slow')],
        isCurrent: () => guard.isCurrent(ticket),
        read: (_) => gate.future,
      );
      source.notifyListeners();
      gate.complete(png);
      expect(await pending, isNull);
      guard.dispose();
      source.dispose();
    },
  );
}
