// Agnes APIHub 协议辅助（检测函数，不新增 ProviderType）。
// 对齐 https://wiki.agnes-ai.com / MODEL_CATALOG：
// - Base: https://apihub.agnes-ai.com/v1
// - 视频：agnes-video-v2.0 / agnes-video-2.5 / agnes-video-2.5-flash
// - 生图：agnes-image-2.x / 2.5-flash（size 档位 + ratio）

import 'provider_type.dart';
import 'xai_profile.dart';

/// Agnes Video 2.5 size 档位（官方：720P / 1080P / 1K / 2K）。
const List<String> agnesVideoSizes = ['720P', '1080P', '1K', '2K'];

/// Agnes 视频常用比例（2.5 / Flash / v2.0 共用）。
const List<String> agnesVideoRatios = [
  '16:9',
  '9:16',
  '1:1',
  '4:3',
  '3:4',
  '21:9',
];

/// Agnes Video 2.5 时长选项（秒；官方允许 4–12，默认 5）。
const List<int> agnesVideoDurationOptions = [4, 5, 8, 12];

/// Agnes Video 2.5 默认时长。
const int agnesVideoDurationDefault = 5;

/// Agnes Image size 档位。
const List<String> agnesImageSizes = ['1K', '2K', '3K', '4K'];

/// Agnes Image 默认 size。
const String agnesImageSizeDefault = '1K';

/// Agnes Image 比例（官方 `ratio` 字段）。
const List<String> agnesImageRatios = [
  '1:1',
  '3:4',
  '4:3',
  '16:9',
  '9:16',
  '2:3',
  '3:2',
  '21:9',
];

/// Agnes Image 默认比例。
const String agnesImageRatioDefault = '1:1';

/// Agnes Video v2.0 推荐时长选项（由 num_frames/frame_rate 映射）。
const List<int> agnesVideoV20DurationOptions = [3, 5, 10, 18];

/// Agnes Video v2.0 默认时长。
const int agnesVideoV20DurationDefault = 5;

bool _hostLooksAgnes(String? baseUrl) {
  final base = (baseUrl ?? '').toLowerCase();
  return base.contains('agnes-ai.com') || base.contains('agnes-ai.cn');
}

bool _isAgnesVideoModelId(String id) {
  return id.contains('agnes-video');
}

bool _isAgnesImageModelId(String id) {
  return id.contains('agnes-image');
}

/// 是否 Agnes 网关 / 视频模型（仅视频协议分支用）。
///
/// 不再用裸 `agnes-` 匹配，避免 `agnes-2.5-flash` 等对话模型误入视频协议。
bool isAgnesProvider({
  String? baseUrl,
  String? imageModel,
  String? videoModel,
}) {
  if (_hostLooksAgnes(baseUrl)) return true;
  final video = (videoModel ?? '').toLowerCase();
  if (_isAgnesVideoModelId(video)) return true;
  final image = (imageModel ?? '').toLowerCase();
  return _isAgnesImageModelId(image);
}

/// 是否应按 Agnes 生图协议发请求（`/images/generations` + size/ratio）。
bool isAgnesImageProvider({
  String? baseUrl,
  String? imageModel,
}) {
  final image = (imageModel ?? '').toLowerCase();
  if (_isAgnesImageModelId(image)) return true;
  // 仅 baseUrl 命中且模型为空时不强制；有模型名时以模型为准，
  // 中转挂 Agnes 域名但跑 gpt-image 时仍走 OpenAI 路径。
  if (image.isEmpty && _hostLooksAgnes(baseUrl)) return true;
  return false;
}

/// 是否应按 Agnes 视频协议发请求。
bool isAgnesVideoProvider({
  String? baseUrl,
  String? videoModel,
}) {
  final video = (videoModel ?? '').toLowerCase();
  if (_isAgnesVideoModelId(video)) return true;
  if (video.isEmpty && _hostLooksAgnes(baseUrl)) return true;
  // 域名是 Agnes 且模型名含 video 关键词时也走 Agnes（中转自定义名）。
  if (_hostLooksAgnes(baseUrl) && video.contains('video')) return true;
  return false;
}

/// Agnes Video V2.0（`agnes-video-v2.0`）：width/height/num_frames 协议。
bool isAgnesVideoV20(String? videoModel) {
  final id = (videoModel ?? '').toLowerCase();
  if (!_isAgnesVideoModelId(id)) return false;
  return id.contains('v2.0') ||
      id.contains('v2_0') ||
      RegExp(r'video[-_]?v?2\.0').hasMatch(id);
}

/// Agnes Video 2.5 Flash：size 仅 720P。
bool isAgnesVideoFlash(String? videoModel) {
  final id = (videoModel ?? '').toLowerCase();
  if (!_isAgnesVideoModelId(id)) return false;
  return id.contains('flash');
}

/// Agnes Video 2.5（含 Flash）异步 Videos 兼容协议。
bool isAgnesVideo25(String? videoModel) {
  if (isAgnesVideoV20(videoModel)) return false;
  final id = (videoModel ?? '').toLowerCase();
  if (_isAgnesVideoModelId(id)) return true;
  // 仅域名命中、无明确 v2.0 时默认 2.5。
  return false;
}

/// Agnes 视频 size 归一。
///
/// - Flash → 强制 720P
/// - 2.5：720P / 1080P / 1K / 2K（旧 960P → 1080P）
/// - v2.0：返回空串（改走 width/height）
String normalizeAgnesVideoSize(String? size, {String? videoModel}) {
  if (isAgnesVideoV20(videoModel)) return '';
  if (isAgnesVideoFlash(videoModel)) return '720P';
  final raw = (size ?? '').trim();
  if (raw.isEmpty) return '720P';
  final upper = raw.toUpperCase();
  if (agnesVideoSizes.contains(upper)) return upper;
  if (upper == '720' || upper == '720P') return '720P';
  if (upper == '1080' || upper == '1080P' || upper == '960' || upper == '960P') {
    return '1080P';
  }
  if (upper == '1K' || upper == '1024') return '1K';
  if (upper == '2K') return '2K';
  final m = RegExp(r'^(\d+)\s*x\s*(\d+)$', caseSensitive: false).firstMatch(raw);
  if (m != null) {
    final w = int.tryParse(m.group(1)!) ?? 0;
    final h = int.tryParse(m.group(2)!) ?? 0;
    final long = w > h ? w : h;
    if (long >= 1800) return '2K';
    if (long >= 1400) return '1080P';
    if (w == h && long >= 1000 && long <= 1100) return '1K';
    return '720P';
  }
  return '720P';
}

/// 秒数 clamp 到 4–12；无效时默认 5（对齐官方）。
int clampAgnesVideoSeconds(int? seconds) {
  final n = seconds;
  if (n == null) return 5;
  if (n < 4) return 4;
  if (n > 12) return 12;
  return n;
}

/// v2.0：将目标秒数映射为 num_frames（frame_rate=24，遵守 8n+1）。
int agnesV20NumFramesForSeconds(int? seconds) {
  final s = seconds ?? agnesVideoV20DurationDefault;
  // 常见档：3→81, 5→121, 10→241, 18→441
  if (s <= 3) return 81;
  if (s <= 6) return 121;
  if (s <= 12) return 241;
  return 441;
}

/// v2.0：按比例给出推荐 width/height（偏 720p 档）。
({int width, int height}) resolveAgnesV20Dimensions(String? aspectRatio) {
  switch ((aspectRatio ?? '').trim()) {
    case '9:16':
      return (width: 768, height: 1152);
    case '1:1':
      return (width: 768, height: 768);
    case '4:3':
      return (width: 1024, height: 768);
    case '3:4':
      return (width: 768, height: 1024);
    case '21:9':
      return (width: 1152, height: 486);
    case '16:9':
    default:
      return (width: 1152, height: 768);
  }
}

/// 网关根：去掉尾 `/` 与末尾 `/v1`。
String resolveAgnesApiHubRoot(String? baseUrl) {
  return (baseUrl ?? '')
      .trim()
      .replaceAll(RegExp(r'/+$'), '')
      .replaceFirst(RegExp(r'/v1$', caseSensitive: false), '');
}

/// 轮询绝对 URL：`{root}/agnesapi?video_id=&model_name=`。
///
/// 2.5 / Flash 建议始终带 [videoModel]；v2.0 可选但传入更稳。
Uri buildAgnesPollUrl({
  required String baseUrl,
  required String jobId,
  String? videoModel,
}) {
  final root = resolveAgnesApiHubRoot(baseUrl);
  final id = jobId.trim();
  final params = <String, String>{'video_id': id};
  final model = (videoModel ?? '').trim();
  if (model.isNotEmpty) params['model_name'] = model;
  return Uri.parse('$root/agnesapi').replace(queryParameters: params);
}

/// Agnes 当前可用的视频 size 档位。
List<String> agnesVideoSizeOptionsFor(String? videoModel) {
  if (isAgnesVideoV20(videoModel)) return const [];
  if (isAgnesVideoFlash(videoModel)) return const ['720P'];
  return List<String>.from(agnesVideoSizes);
}

/// Agnes 视频时长选项（随模型族切换）。
List<int> agnesVideoDurationOptionsFor(String? videoModel) {
  if (isAgnesVideoV20(videoModel)) {
    return List<int>.from(agnesVideoV20DurationOptions);
  }
  return List<int>.from(agnesVideoDurationOptions);
}

/// Agnes 视频默认时长。
int agnesVideoDurationDefaultFor(String? videoModel) {
  if (isAgnesVideoV20(videoModel)) return agnesVideoV20DurationDefault;
  return agnesVideoDurationDefault;
}

/// Agnes Image size 归一到 1K–4K。
String normalizeAgnesImageSize(String? size) {
  final raw = (size ?? '').trim();
  if (raw.isEmpty) return agnesImageSizeDefault;
  final upper = raw.toUpperCase();
  if (agnesImageSizes.contains(upper)) return upper;
  final m = RegExp(r'^(\d+)\s*x\s*(\d+)$', caseSensitive: false).firstMatch(raw);
  if (m != null) {
    final w = int.tryParse(m.group(1)!) ?? 0;
    final h = int.tryParse(m.group(2)!) ?? 0;
    final long = w > h ? w : h;
    if (long >= 3500) return '4K';
    if (long >= 2500) return '3K';
    if (long >= 1500) return '2K';
    return '1K';
  }
  return agnesImageSizeDefault;
}

/// Agnes Image ratio 归一；非法则默认 1:1。
String normalizeAgnesImageRatio(String? ratio) {
  final r = (ratio ?? '').trim();
  if (r.isEmpty) return agnesImageRatioDefault;
  if (agnesImageRatios.contains(r)) return r;
  return agnesImageRatioDefault;
}

/// 完成后是否需要补拉 `/content`。
///
/// - 官方 xAI（[isNativeXaiVideoProvider]）/ Agnes：否
/// - 中转 + `grok-imagine-video`：是（创建走 generations，完成态常只给 `/content`）
/// - [isXai] 仅作兼容：为 true 且未提供 provider/base 时视为官方跳过
bool shouldFetchVideoContent({
  required bool isXai,
  String? baseUrl,
  String? imageModel,
  String? videoModel,
  ProviderType? providerType,
}) {
  if (isAgnesVideoProvider(baseUrl: baseUrl, videoModel: videoModel) ||
      isAgnesProvider(
        baseUrl: baseUrl,
        imageModel: imageModel,
        videoModel: videoModel,
      )) {
    return false;
  }
  if (isNativeXaiVideoProvider(
    providerType: providerType,
    baseUrl: baseUrl,
  )) {
    return false;
  }
  // 兼容旧调用：只传 isXai:true、无 base/type 时仍跳过
  if (isXai &&
      providerType == null &&
      (baseUrl == null || baseUrl.trim().isEmpty)) {
    return false;
  }
  return true;
}
