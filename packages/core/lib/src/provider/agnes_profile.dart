// Agnes APIHub 视频协议辅助（检测函数，不新增 ProviderType）。

import 'provider_type.dart';
import 'xai_profile.dart';

/// Agnes Video 2.5：size 档位。
const List<String> agnesVideoSizes = ['720P', '960P', '2K'];

/// Agnes 视频常用比例。
const List<String> agnesVideoRatios = [
  '16:9',
  '9:16',
  '1:1',
  '4:3',
  '3:4',
  '21:9',
];

/// Agnes 视频时长选项（秒）。
const List<int> agnesVideoDurationOptions = [4, 8, 12];

/// Agnes 视频默认时长。
const int agnesVideoDurationDefault = 8;

/// 是否 Agnes 提供商（baseUrl / 模型名启发式）。
bool isAgnesProvider({
  String? baseUrl,
  String? imageModel,
  String? videoModel,
}) {
  final base = (baseUrl ?? '').toLowerCase();
  final image = (imageModel ?? '').toLowerCase();
  final video = (videoModel ?? '').toLowerCase();
  return base.contains('agnes-ai.com') ||
      image.contains('agnes-image') ||
      video.contains('agnes-video') ||
      video.contains('agnes-');
}

/// Flash 仅支持 720P。
bool isAgnesVideoFlash(String? videoModel) {
  return (videoModel ?? '').toLowerCase().contains('flash');
}

/// Agnes 视频 size 归一：Flash 强制 720P；档位 / WxH 兼容。
String normalizeAgnesVideoSize(String? size, {String? videoModel}) {
  if (isAgnesVideoFlash(videoModel)) return '720P';
  final raw = (size ?? '').trim();
  if (raw.isEmpty) return '720P';
  final upper = raw.toUpperCase();
  if (agnesVideoSizes.contains(upper)) return upper;
  if (upper == '720' || upper == '720P') return '720P';
  if (upper == '960' || upper == '960P') return '960P';
  if (upper == '2K' || upper == '1080P' || upper == '1080') return '2K';
  final m = RegExp(r'^(\d+)\s*x\s*(\d+)$', caseSensitive: false).firstMatch(raw);
  if (m != null) {
    final w = int.tryParse(m.group(1)!) ?? 0;
    final h = int.tryParse(m.group(2)!) ?? 0;
    final long = w > h ? w : h;
    if (long >= 1800) return '2K';
    if (long > 1280) return '960P';
    return '720P';
  }
  return '720P';
}

/// 秒数 clamp 到 4–12；无效时默认 5（对齐现网）。
int clampAgnesVideoSeconds(int? seconds) {
  final n = seconds;
  if (n == null) return 5;
  if (n < 4) return 4;
  if (n > 12) return 12;
  return n;
}

/// 网关根：去掉尾 `/` 与末尾 `/v1`。
String resolveAgnesApiHubRoot(String? baseUrl) {
  return (baseUrl ?? '')
      .trim()
      .replaceAll(RegExp(r'/+$'), '')
      .replaceFirst(RegExp(r'/v1$', caseSensitive: false), '');
}

/// 轮询绝对 URL：`{root}/agnesapi?video_id=&model_name=`。
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

/// Agnes 当前可用的 size 档位（Flash 仅 720P）。
List<String> agnesVideoSizeOptionsFor(String? videoModel) {
  if (isAgnesVideoFlash(videoModel)) return const ['720P'];
  return List<String>.from(agnesVideoSizes);
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
  if (isAgnesProvider(
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
