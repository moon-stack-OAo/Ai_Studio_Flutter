/// 生图会话与条目模型。

enum ImageGenMode {
  text,
  edit;

  static ImageGenMode? tryParse(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'text':
      case 'txt2img':
        return ImageGenMode.text;
      case 'edit':
      case 'img2img':
        return ImageGenMode.edit;
      default:
        return null;
    }
  }

  String get wire => name;
}

enum ImageItemStatus {
  loading,
  done,
  error;

  static ImageItemStatus? tryParse(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'loading':
        return ImageItemStatus.loading;
      case 'done':
        return ImageItemStatus.done;
      case 'error':
        return ImageItemStatus.error;
      default:
        return null;
    }
  }

  String get wire => name;
}

enum ImageRefType {
  b64,
  url,
  file;

  static ImageRefType? tryParse(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'b64':
        return ImageRefType.b64;
      case 'url':
        return ImageRefType.url;
      case 'file':
        return ImageRefType.file;
      default:
        return null;
    }
  }

  String get wire => name;
}

/// 单张图引用：b64 / url / 本地文件路径。
class ImageRef {
  const ImageRef({
    required this.type,
    required this.src,
    this.revisedPrompt,
  });

  final ImageRefType type;

  /// b64：可为 data URL 或纯 base64；url：远端地址；file：本地路径。
  final String src;
  final String? revisedPrompt;

  ImageRef copyWith({
    ImageRefType? type,
    String? src,
    String? revisedPrompt,
    bool clearRevisedPrompt = false,
  }) {
    return ImageRef(
      type: type ?? this.type,
      src: src ?? this.src,
      revisedPrompt: clearRevisedPrompt
          ? null
          : (revisedPrompt ?? this.revisedPrompt),
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.wire,
        'src': src,
        if (revisedPrompt != null && revisedPrompt!.isNotEmpty)
          'revisedPrompt': revisedPrompt,
      };

  factory ImageRef.fromJson(Map<String, dynamic> json) {
    return ImageRef(
      type: ImageRefType.tryParse(json['type']?.toString()) ?? ImageRefType.url,
      src: json['src']?.toString() ?? '',
      revisedPrompt: json['revisedPrompt']?.toString(),
    );
  }
}

class ImageItem {
  const ImageItem({
    required this.id,
    required this.createdAt,
    required this.mode,
    required this.prompt,
    this.model = '',
    this.providerName = '',
    this.images = const [],
    this.refPreview,
    this.n = 1,
    this.size,
    this.aspectRatio,
    this.quality,
    this.status = ImageItemStatus.done,
    this.errorMessage,
  });

  final String id;
  final int createdAt;
  final ImageGenMode mode;
  final String prompt;
  final String model;
  final String providerName;
  final List<ImageRef> images;
  final String? refPreview;
  final int n;
  final String? size;
  final String? aspectRatio;
  final String? quality;
  final ImageItemStatus status;
  final String? errorMessage;

  ImageItem copyWith({
    String? id,
    int? createdAt,
    ImageGenMode? mode,
    String? prompt,
    String? model,
    String? providerName,
    List<ImageRef>? images,
    String? refPreview,
    int? n,
    String? size,
    String? aspectRatio,
    String? quality,
    ImageItemStatus? status,
    String? errorMessage,
    bool clearRefPreview = false,
    bool clearSize = false,
    bool clearAspectRatio = false,
    bool clearQuality = false,
    bool clearErrorMessage = false,
  }) {
    return ImageItem(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      mode: mode ?? this.mode,
      prompt: prompt ?? this.prompt,
      model: model ?? this.model,
      providerName: providerName ?? this.providerName,
      images: images ?? this.images,
      refPreview:
          clearRefPreview ? null : (refPreview ?? this.refPreview),
      n: n ?? this.n,
      size: clearSize ? null : (size ?? this.size),
      aspectRatio:
          clearAspectRatio ? null : (aspectRatio ?? this.aspectRatio),
      quality: clearQuality ? null : (quality ?? this.quality),
      status: status ?? this.status,
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt,
        'mode': mode.wire,
        'prompt': prompt,
        'model': model,
        'providerName': providerName,
        'images': images.map((e) => e.toJson()).toList(),
        if (refPreview != null) 'refPreview': refPreview,
        'n': n,
        if (size != null) 'size': size,
        if (aspectRatio != null) 'aspectRatio': aspectRatio,
        if (quality != null) 'quality': quality,
        'status': status.wire,
        if (errorMessage != null) 'errorMessage': errorMessage,
      };

  factory ImageItem.fromJson(Map<String, dynamic> json) {
    final imgs = <ImageRef>[];
    final rawImgs = json['images'];
    if (rawImgs is List) {
      for (final e in rawImgs) {
        if (e is Map) {
          imgs.add(ImageRef.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return ImageItem(
      id: json['id']?.toString() ?? '',
      createdAt:
          (json['createdAt'] is num) ? (json['createdAt'] as num).toInt() : 0,
      mode: ImageGenMode.tryParse(json['mode']?.toString()) ??
          ImageGenMode.text,
      prompt: json['prompt']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
      providerName: json['providerName']?.toString() ?? '',
      images: imgs,
      refPreview: json['refPreview']?.toString(),
      n: (json['n'] is num) ? (json['n'] as num).toInt() : 1,
      size: json['size']?.toString(),
      aspectRatio: json['aspectRatio']?.toString(),
      quality: json['quality']?.toString(),
      status: ImageItemStatus.tryParse(json['status']?.toString()) ??
          ImageItemStatus.done,
      errorMessage: json['errorMessage']?.toString(),
    );
  }
}

class ImageSession {
  const ImageSession({
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
  final List<ImageItem> items;

  ImageSession copyWith({
    String? id,
    String? title,
    int? createdAt,
    int? updatedAt,
    List<ImageItem>? items,
  }) {
    return ImageSession(
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

  factory ImageSession.fromJson(Map<String, dynamic> json) {
    final items = <ImageItem>[];
    final raw = json['items'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          items.add(ImageItem.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return ImageSession(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '新生图',
      createdAt:
          (json['createdAt'] is num) ? (json['createdAt'] as num).toInt() : 0,
      updatedAt:
          (json['updatedAt'] is num) ? (json['updatedAt'] as num).toInt() : 0,
      items: items,
    );
  }
}

/// 持久化快照。
class ImageStoreSnapshot {
  const ImageStoreSnapshot({
    required this.sessions,
    required this.activeId,
  });

  final List<ImageSession> sessions;
  final String activeId;
}
