import 'dart:io';
import 'dart:typed_data';

import '../security/url_safety.dart';
import 'video_client.dart';
import 'video_models.dart';
import 'video_poster_store.dart';

/// 从本地/远程成片抽一帧为 JPEG。由各 app 注入（如 media_kit），
/// 避免 `packages/core` 依赖原生播放库。
abstract class VideoFrameExtractor {
  /// 返回 JPEG 字节；失败返回 `null`。
  Future<Uint8List?> extractJpeg(
    String videoPath, {
    Duration at = const Duration(milliseconds: 400),
  });
}

/// VID-QUEUE 封面解析与抽帧缓存。
///
/// 来源优先级：任务/CDN `posterUrl` → 本机抽帧缓存 → `null`（UI 占位）。
class VideoPosterService {
  VideoPosterService({
    required this.store,
    this._extractor,
  });

  final VideoPosterStore store;
  VideoFrameExtractor? _extractor;

  /// 运行时注入抽帧实现（app 启动后设置）。
  void setExtractor(VideoFrameExtractor? extractor) {
    _extractor = extractor;
  }

  /// 是否为可直接展示的远程海报 URL。
  static bool isRemotePosterUrl(String? raw) {
    final u = (raw ?? '').trim();
    if (u.isEmpty) return false;
    final uri = Uri.tryParse(u);
    if (uri == null || !uri.hasScheme) return false;
    try {
      assertSafeHttpUrl(uri);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 同步优先路径：已有远程 poster / 已记录本地路径 / 内存 key。
  /// 不触发抽帧；UI 可先据此渲染，再 [ensureLocalPoster]。
  String? peekPoster(VideoItem item) {
    if (isRemotePosterUrl(item.posterUrl)) return item.posterUrl!.trim();
    final local = (item.posterLocalPath ?? '').trim();
    if (local.isEmpty) return null;
    if (local.startsWith('memory-poster://')) return local;
    if (File(local).existsSync()) return local;
    return null;
  }

  /// 解析展示用封面：远程 URL 或本地文件路径；无则 `null`。
  Future<String?> resolvePoster(VideoItem item) async {
    if (item.status != VideoItemStatus.success) return null;
    if (isRemotePosterUrl(item.posterUrl)) return item.posterUrl!.trim();

    final recorded = (item.posterLocalPath ?? '').trim();
    if (recorded.isNotEmpty) {
      if (recorded.startsWith('memory-poster://')) return recorded;
      if (await File(recorded).exists()) return recorded;
    }

    final cached = await store.pathFor(item.id);
    if (cached != null && cached.isNotEmpty) {
      if (cached.startsWith('memory-poster://')) return cached;
      if (await File(cached).exists()) return cached;
    }

    return ensureLocalPoster(item);
  }

  /// 对可播成片抽帧并写入 [VideoPosterStore]；已有缓存则直接返回。
  Future<String?> ensureLocalPoster(VideoItem item) async {
    if (item.status != VideoItemStatus.success) return null;
    if (item.needsMaterialize) return null;

    final existing = await store.pathFor(item.id);
    if (existing != null && existing.isNotEmpty) {
      if (existing.startsWith('memory-poster://')) return existing;
      if (await File(existing).exists()) return existing;
    }

    final recorded = (item.posterLocalPath ?? '').trim();
    if (recorded.isNotEmpty &&
        !recorded.startsWith('memory-poster://') &&
        await File(recorded).exists()) {
      return recorded;
    }

    final extractor = _extractor;
    if (extractor == null) return null;

    final source = _localExtractSource(item);
    if (source == null) return null;

    try {
      final bytes = await extractor.extractJpeg(source);
      if (bytes == null || bytes.isEmpty) return null;
      return await store.saveJpeg(bytes, item.id);
    } catch (_) {
      return null;
    }
  }

  /// 仅本地文件可抽帧（远程直链留给 posterUrl / 占位）。
  String? _localExtractSource(VideoItem item) {
    for (final candidate in [
      item.localPath,
      item.videoUrl,
    ]) {
      final p = (candidate ?? '').trim();
      if (p.isEmpty) continue;
      if (p.startsWith('memory://')) continue;
      if (RegExp(r'^https?://', caseSensitive: false).hasMatch(p)) continue;
      if (!isPlayableVideoPath(p)) continue;
      if (!File(p).existsSync()) continue;
      return p;
    }
    return null;
  }

  Future<void> clearAll() => store.clearAll();

  Future<int> estimateBytes() => store.estimateBytes();
}
