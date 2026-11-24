import 'dart:io';

import 'package:flutter/foundation.dart';

import '../chat/chat_attach.dart';
import 'image_asset_store.dart';
import 'image_models.dart';
import 'image_session_storage.dart';

/// Invalidates asynchronous draft work on edits, navigation or generation.
/// Listeners are deliberately conservative: even switching away and back must
/// not make an old result current again.
class MediaDraftRestoreGuard {
  MediaDraftRestoreGuard(Iterable<Listenable> sources)
    : _sources = List.of(sources) {
    for (final source in _sources) {
      source.addListener(invalidate);
    }
  }

  final List<Listenable> _sources;
  Object? _ticket;
  bool _disposed = false;

  Object begin() => _ticket = Object();
  void invalidate() => _ticket = null;
  bool isCurrent(Object ticket) => !_disposed && identical(ticket, _ticket);

  void dispose() {
    _disposed = true;
    invalidate();
    for (final source in _sources) {
      source.removeListener(invalidate);
    }
  }
}

class MediaDraftReference {
  const MediaDraftReference(this.ref, this.bytes);
  final ImageRef ref;
  final Uint8List bytes;
  String get fileName {
    if (ref.type == ImageRefType.file) {
      return ref.src.replaceAll('\\', '/').split('/').last;
    }
    return sniffImageMime(bytes) == 'image/jpeg'
        ? 'image.jpg'
        : sniffImageMime(bytes) == 'image/webp'
        ? 'image.webp'
        : 'image.png';
  }
}

/// History refill is local-only; explicit download/use-as-reference is separate.
Future<Uint8List?> readLocalMediaDraftReference(ImageRef ref) async {
  try {
    if (ref.type == ImageRefType.b64) {
      if (ref.src.length > maxImageB64SrcChars) return null;
      if (ref.src.startsWith('data:') &&
          !RegExp(
            r'^data:image/(png|jpeg|jpg|webp);base64,',
            caseSensitive: false,
          ).hasMatch(ref.src)) {
        return null;
      }
      return decodeImageB64(ref.src);
    }
    if (ref.type != ImageRefType.file || ref.src.trim().isEmpty) return null;
    final file = File(ref.src);
    if (await file.length() > maxChatAttachmentBytes) return null;
    return await file.readAsBytes();
  } catch (_) {
    return null;
  }
}

Future<MediaDraftReference?> selectMediaDraftReference(
  List<ImageRef> refs, {
  Future<Uint8List?> Function(ImageRef) read = readLocalMediaDraftReference,
  required bool Function() isCurrent,
}) async {
  for (final ref in refs) {
    if (!isCurrent()) return null;
    if (ref.type == ImageRefType.url) continue;
    if (ref.type == ImageRefType.b64 && ref.src.length > maxImageB64SrcChars) {
      continue;
    }
    try {
      final bytes = await read(ref);
      if (!isCurrent()) return null;
      if (bytes == null || validateChatAttachmentBytes(bytes) != null) continue;
      return MediaDraftReference(ref, bytes);
    } catch (_) {
      // Missing/unreadable assets do not prevent restoring text and parameters.
    }
  }
  return null;
}
