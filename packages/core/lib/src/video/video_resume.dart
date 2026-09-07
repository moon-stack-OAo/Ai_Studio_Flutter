import 'package:http/http.dart' as http;

import '../chat/chat_errors.dart';
import '../provider/provider_config.dart';
import 'video_client.dart';
import 'video_models.dart';
import 'video_session_repository.dart';

/// 单条恢复结果。
class VideoResumeResult {
  const VideoResumeResult({
    required this.sessionId,
    required this.itemId,
    this.job,
    this.error,
  });

  final String sessionId;
  final String itemId;
  final VideoJob? job;
  final Object? error;
}

/// 解析提供商：优先条目 [VideoItem.providerId]，否则回退当前活跃。
typedef VideoProviderResolver = ProviderConfig? Function(String? providerId);

/// 对 pending_resume 续 waitJob；失败/abort 回 pending_resume。
Future<List<VideoResumeResult>> resumePendingJobs({
  required VideoSessionRepository repository,
  required OpenAiCompatibleVideoClient client,
  required VideoProviderResolver resolveProvider,
  Duration? interval,
  Duration? timeout,
  bool Function()? isCancelled,
  void Function(String sessionId, String itemId, VideoJob job)? onProgress,
  http.Client? httpClient,
}) async {
  final pending = repository.pendingResumeItems;
  if (pending.isEmpty) return const [];

  final results = <VideoResumeResult>[];
  for (final entry in pending) {
    if (isCancelled?.call() == true) break;

    final sessionId = entry.sessionId;
    final item = entry.item;
    final jobId = item.jobId?.trim() ?? '';
    final provider = resolveProvider(
      item.providerId.isEmpty ? null : item.providerId,
    );

    if (provider == null ||
        provider.baseUrl.trim().isEmpty ||
        jobId.isEmpty) {
      await repository.failItem(
        sessionId,
        item.id,
        '无法恢复：缺少提供商或任务 ID',
      );
      results.add(
        VideoResumeResult(
          sessionId: sessionId,
          itemId: item.id,
          error: StateError('missing provider or jobId'),
        ),
      );
      continue;
    }

    await repository.updateItem(
      sessionId,
      item.id,
      status: VideoItemStatus.loading,
      needsResume: false,
    );

    try {
      final job = await client.waitJob(
        baseUrl: provider.baseUrl,
        apiKey: provider.apiKey,
        jobId: jobId,
        providerType: provider.type,
        videoModel: provider.videoModel,
        assetStore: repository.assetStore,
        materializeId: item.id,
        interval: interval,
        timeout: timeout,
        isCancelled: isCancelled,
        client: httpClient,
        onProgress: (j) {
          final early = earlyPlayableVideoPath(j);
          VideoItem? live;
          for (final s in repository.sessions) {
            if (s.id != sessionId) continue;
            for (final i in s.items) {
              if (i.id == item.id) {
                live = i;
                break;
              }
            }
          }
          final earlyUrl = early.isEmpty ? null : early;
          final remote = early.isNotEmpty &&
                  RegExp(r'^https?://', caseSensitive: false).hasMatch(early)
              ? early
              : j.remoteVideoUrl;
          repository.updateItem(
            sessionId,
            item.id,
            status: VideoItemStatus.loading,
            progress: j.progress,
            jobId: j.jobId.isNotEmpty ? j.jobId : null,
            videoUrl: earlyUrl != null && earlyUrl != live?.videoUrl
                ? earlyUrl
                : null,
            remoteVideoUrl:
                remote != null && remote != live?.remoteVideoUrl
                    ? remote
                    : null,
            persist: j.jobId.isNotEmpty || early.isNotEmpty,
          );
          onProgress?.call(sessionId, item.id, j);
        },
      );

      await applyVideoJobCompletion(
        repository: repository,
        sessionId: sessionId,
        item: item,
        job: job,
      );
      results.add(
        VideoResumeResult(
          sessionId: sessionId,
          itemId: item.id,
          job: job,
        ),
      );
    } catch (e) {
      if (isAbortLike(e) || e is ChatAbortException) {
        await repository.markPendingResume(
          sessionId,
          item.id,
          errorMessage: '已停止轮询，可手动恢复',
        );
        results.add(
          VideoResumeResult(
            sessionId: sessionId,
            itemId: item.id,
            error: e,
          ),
        );
        break;
      }
      if (e is VideoJobTimeoutException) {
        await repository.markPendingResume(
          sessionId,
          item.id,
          errorMessage: e.message,
        );
      } else {
        await repository.failItem(
          sessionId,
          item.id,
          toChatErrorMessage(e, '恢复任务失败'),
        );
      }
      results.add(
        VideoResumeResult(
          sessionId: sessionId,
          itemId: item.id,
          error: e,
        ),
      );
    }
  }
  return results;
}

/// 完成态写入：仅真正可播才 success；否则 markNeedsMaterialize。
Future<void> applyVideoJobCompletion({
  required VideoSessionRepository repository,
  required String sessionId,
  required VideoItem item,
  required VideoJob job,
}) async {
  final playable = resolvePlayableVideoPath(job);
  final remote = pickRemoteVideoUrl(job, item);
  final needsMat = job.needsMaterialize || playable.isEmpty;

  if (job.status == VideoJobWireStatus.completed &&
      playable.isNotEmpty &&
      !needsMat) {
    await repository.completeItem(
      sessionId,
      item.id,
      videoUrl: playable,
      remoteVideoUrl: remote.isEmpty ? null : remote,
      localPath: job.localPath ??
          (playable.startsWith('http') ? null : playable),
      needsMaterialize: false,
    );
    return;
  }

  if (job.status == VideoJobWireStatus.completed) {
    final detail = (job.errorMessage?.trim().isNotEmpty == true)
        ? job.errorMessage!
        : (playable.isEmpty
            ? '视频已生成但本地加载失败，可尝试重新加载'
            : '视频已生成但本地加载失败，可尝试重新加载');
    await repository.markNeedsMaterialize(
      sessionId,
      item.id,
      errorMessage: detail,
      remoteVideoUrl: remote.isEmpty ? null : remote,
      videoUrl: playable.isEmpty ? null : playable,
      jobId: job.jobId.isNotEmpty ? job.jobId : item.jobId,
    );
    return;
  }

  await repository.failItem(
    sessionId,
    item.id,
    job.errorMessage ?? '视频生成失败',
  );
}

/// 供 UI：按仓库 + 活跃提供商解析。
VideoProviderResolver defaultVideoProviderResolver({
  required List<ProviderConfig> Function() providers,
  required ProviderConfig? Function() activeProvider,
}) {
  return (String? providerId) {
    if (providerId != null && providerId.isNotEmpty) {
      for (final p in providers()) {
        if (p.id == providerId) return p;
      }
    }
    return activeProvider();
  };
}
