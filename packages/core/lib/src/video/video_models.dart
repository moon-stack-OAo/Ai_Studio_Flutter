/// 生视频会话与条目模型。

enum VideoGenMode {
  text,
  image;

  static VideoGenMode? tryParse(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'text':
      case 'txt2video':
        return VideoGenMode.text;
      case 'image':
      case 'img2video':
        return VideoGenMode.image;
      default:
        return null;
    }
  }

  String get wire => name;

  String get apiMode =>
      this == VideoGenMode.image ? 'img2video' : 'txt2video';
}

enum VideoItemStatus {
  loading,
  pendingResume,
  success,
  error,
  abandoned;

  static VideoItemStatus? tryParse(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'loading':
        return VideoItemStatus.loading;
      case 'pending_resume':
      case 'pendingresume':
        return VideoItemStatus.pendingResume;
      case 'success':
      case 'done':
      case 'completed':
        return VideoItemStatus.success;
      case 'error':
      case 'failed':
        return VideoItemStatus.error;
      case 'abandoned':
        return VideoItemStatus.abandoned;
      default:
        return null;
    }
  }

  String get wire => switch (this) {
        VideoItemStatus.loading => 'loading',
        VideoItemStatus.pendingResume => 'pending_resume',
        VideoItemStatus.success => 'success',
        VideoItemStatus.error => 'error',
        VideoItemStatus.abandoned => 'abandoned',
      };
}

/// 上游任务归一化状态（轮询用）。
enum VideoJobWireStatus {
  queued,
  inProgress,
  completed,
  failed;

  static VideoJobWireStatus normalize(String? raw) {
    final s = (raw ?? '').trim().toLowerCase();
    if (s == 'completed' ||
        s == 'done' ||
        s == 'success' ||
        s == 'succeeded') {
      return VideoJobWireStatus.completed;
    }
    if (s == 'failed' ||
        s == 'expired' ||
        s == 'error' ||
        s == 'cancelled' ||
        s == 'canceled') {
      return VideoJobWireStatus.failed;
    }
    if (s == 'queued' || s == 'pending') {
      return VideoJobWireStatus.queued;
    }
    if (s == 'in_progress' ||
        s == 'processing' ||
        s == 'running') {
      return VideoJobWireStatus.inProgress;
    }
    if (s.isEmpty) return VideoJobWireStatus.queued;
    return VideoJobWireStatus.inProgress;
  }

  bool get isTerminal =>
      this == VideoJobWireStatus.completed ||
      this == VideoJobWireStatus.failed;
}

/// 上游视频任务快照。
class VideoJob {
  const VideoJob({
    this.jobId = '',
    this.status = VideoJobWireStatus.queued,
    this.progress,
    this.videoUrl,
    this.remoteVideoUrl,
    this.localPath,
    this.errorMessage,
    this.needsMaterialize = false,
  });

  final String jobId;
  final VideoJobWireStatus status;
  final double? progress;
  final String? videoUrl;
  final String? remoteVideoUrl;
  final String? localPath;
  final String? errorMessage;
  final bool needsMaterialize;

  VideoJob copyWith({
    String? jobId,
    VideoJobWireStatus? status,
    double? progress,
    String? videoUrl,
    String? remoteVideoUrl,
    String? localPath,
    String? errorMessage,
    bool? needsMaterialize,
    bool clearProgress = false,
    bool clearVideoUrl = false,
    bool clearRemoteVideoUrl = false,
    bool clearLocalPath = false,
    bool clearErrorMessage = false,
  }) {
    return VideoJob(
      jobId: jobId ?? this.jobId,
      status: status ?? this.status,
      progress: clearProgress ? null : (progress ?? this.progress),
      videoUrl: clearVideoUrl ? null : (videoUrl ?? this.videoUrl),
      remoteVideoUrl: clearRemoteVideoUrl
          ? null
          : (remoteVideoUrl ?? this.remoteVideoUrl),
      localPath: clearLocalPath ? null : (localPath ?? this.localPath),
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      needsMaterialize: needsMaterialize ?? this.needsMaterialize,
    );
  }
}

class VideoItem {
  const VideoItem({
    required this.id,
    required this.createdAt,
    required this.mode,
    required this.prompt,
    this.model = '',
    this.providerId = '',
    this.providerName = '',
    this.status = VideoItemStatus.success,
    this.jobId,
    this.progress,
    this.duration,
    this.aspectRatio,
    this.size,
    this.resolution,
    this.videoUrl,
    this.remoteVideoUrl,
    this.localPath,
    this.refPreview,
    this.errorMessage,
    this.needsResume = false,
    this.needsMaterialize = false,
  });

  final String id;
  final int createdAt;
  final VideoGenMode mode;
  final String prompt;
  final String model;
  final String providerId;
  final String providerName;
  final VideoItemStatus status;
  final String? jobId;
  final double? progress;
  final int? duration;
  final String? aspectRatio;
  final String? size;
  final String? resolution;
  final String? videoUrl;
  final String? remoteVideoUrl;
  final String? localPath;
  final String? refPreview;
  final String? errorMessage;
  final bool needsResume;
  /// 已生成但本地不可播；UI 应露出「重新加载」。
  final bool needsMaterialize;

  VideoItem copyWith({
    String? id,
    int? createdAt,
    VideoGenMode? mode,
    String? prompt,
    String? model,
    String? providerId,
    String? providerName,
    VideoItemStatus? status,
    String? jobId,
    double? progress,
    int? duration,
    String? aspectRatio,
    String? size,
    String? resolution,
    String? videoUrl,
    String? remoteVideoUrl,
    String? localPath,
    String? refPreview,
    String? errorMessage,
    bool? needsResume,
    bool? needsMaterialize,
    bool clearJobId = false,
    bool clearProgress = false,
    bool clearDuration = false,
    bool clearAspectRatio = false,
    bool clearSize = false,
    bool clearResolution = false,
    bool clearVideoUrl = false,
    bool clearRemoteVideoUrl = false,
    bool clearLocalPath = false,
    bool clearRefPreview = false,
    bool clearErrorMessage = false,
  }) {
    return VideoItem(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      mode: mode ?? this.mode,
      prompt: prompt ?? this.prompt,
      model: model ?? this.model,
      providerId: providerId ?? this.providerId,
      providerName: providerName ?? this.providerName,
      status: status ?? this.status,
      jobId: clearJobId ? null : (jobId ?? this.jobId),
      progress: clearProgress ? null : (progress ?? this.progress),
      duration: clearDuration ? null : (duration ?? this.duration),
      aspectRatio:
          clearAspectRatio ? null : (aspectRatio ?? this.aspectRatio),
      size: clearSize ? null : (size ?? this.size),
      resolution:
          clearResolution ? null : (resolution ?? this.resolution),
      videoUrl: clearVideoUrl ? null : (videoUrl ?? this.videoUrl),
      remoteVideoUrl: clearRemoteVideoUrl
          ? null
          : (remoteVideoUrl ?? this.remoteVideoUrl),
      localPath: clearLocalPath ? null : (localPath ?? this.localPath),
      refPreview:
          clearRefPreview ? null : (refPreview ?? this.refPreview),
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      needsResume: needsResume ?? this.needsResume,
      needsMaterialize: needsMaterialize ?? this.needsMaterialize,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt,
        'mode': mode.wire,
        'prompt': prompt,
        'model': model,
        'providerId': providerId,
        'providerName': providerName,
        'status': status.wire,
        if (jobId != null && jobId!.isNotEmpty) 'jobId': jobId,
        if (progress != null) 'progress': progress,
        if (duration != null) 'duration': duration,
        if (aspectRatio != null) 'aspectRatio': aspectRatio,
        if (size != null) 'size': size,
        if (resolution != null) 'resolution': resolution,
        if (videoUrl != null && videoUrl!.isNotEmpty) 'videoUrl': videoUrl,
        if (remoteVideoUrl != null && remoteVideoUrl!.isNotEmpty)
          'remoteVideoUrl': remoteVideoUrl,
        if (localPath != null && localPath!.isNotEmpty) 'localPath': localPath,
        if (refPreview != null) 'refPreview': refPreview,
        if (errorMessage != null) 'errorMessage': errorMessage,
        'needsResume': needsResume,
        'needsMaterialize': needsMaterialize,
      };

  factory VideoItem.fromJson(Map<String, dynamic> json) {
    return VideoItem(
      id: json['id']?.toString() ?? '',
      createdAt:
          (json['createdAt'] is num) ? (json['createdAt'] as num).toInt() : 0,
      mode: VideoGenMode.tryParse(json['mode']?.toString()) ??
          VideoGenMode.text,
      prompt: json['prompt']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
      providerId: json['providerId']?.toString() ?? '',
      providerName: json['providerName']?.toString() ?? '',
      status: VideoItemStatus.tryParse(json['status']?.toString()) ??
          VideoItemStatus.success,
      jobId: json['jobId']?.toString(),
      progress: (json['progress'] is num)
          ? (json['progress'] as num).toDouble()
          : null,
      duration:
          (json['duration'] is num) ? (json['duration'] as num).toInt() : null,
      aspectRatio: json['aspectRatio']?.toString(),
      size: json['size']?.toString(),
      resolution: json['resolution']?.toString(),
      videoUrl: json['videoUrl']?.toString(),
      remoteVideoUrl: json['remoteVideoUrl']?.toString(),
      localPath: json['localPath']?.toString(),
      refPreview: json['refPreview']?.toString(),
      errorMessage: json['errorMessage']?.toString(),
      needsResume: json['needsResume'] == true,
      needsMaterialize: json['needsMaterialize'] == true,
    );
  }
}

class VideoSession {
  const VideoSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.items = const [],
  });

  final String id;
  final String title;
  final int createdAt;
  final int updatedAt;
  final List<VideoItem> items;

  VideoSession copyWith({
    String? id,
    String? title,
    int? createdAt,
    int? updatedAt,
    List<VideoItem>? items,
  }) {
    return VideoSession(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      items: items ?? this.items,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'items': items.map((e) => e.toJson()).toList(),
      };

  factory VideoSession.fromJson(Map<String, dynamic> json) {
    final items = <VideoItem>[];
    final raw = json['items'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          items.add(VideoItem.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return VideoSession(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '新视频',
      createdAt:
          (json['createdAt'] is num) ? (json['createdAt'] as num).toInt() : 0,
      updatedAt:
          (json['updatedAt'] is num) ? (json['updatedAt'] as num).toInt() : 0,
      items: items,
    );
  }
}

/// 持久化快照。
class VideoStoreSnapshot {
  const VideoStoreSnapshot({
    required this.sessions,
    required this.activeId,
  });

  final List<VideoSession> sessions;
  final String activeId;
}
