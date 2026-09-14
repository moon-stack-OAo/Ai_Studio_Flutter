import 'dart:typed_data';

import '../image/image_models.dart';

/// 每条用户消息最多附图张数（CHAT-ATTACH）。
const int maxChatAttachments = 4;

/// 单张原始字节上限（4 MiB）。
const int maxChatAttachmentBytes = 4 << 20;

/// 允许的 MIME（含 jpg 别名）。
const Set<String> allowedChatAttachmentMimes = {
  'image/png',
  'image/jpeg',
  'image/jpg',
  'image/webp',
};

/// 落盘 id 前缀（与生图 `image_cache` 分轨）。
const String chatAttachmentIdPrefix = 'chat_';

/// 视觉模型启发式：id 含下列子串（大小写不敏感）则允许附图。
bool supportsChatVision(String? chatModel) {
  final id = (chatModel ?? '').trim().toLowerCase();
  if (id.isEmpty) return false;
  const needles = <String>[
    'vision',
    'gpt-4o',
    'gpt-4.1',
    'gpt-5',
    'o1',
    'o3',
    'o4',
    'gemini',
    'claude-3',
    'claude-4',
    'claude-sonnet',
    'claude-opus',
    'llava',
    'grok',
  ];
  for (final n in needles) {
    if (id.contains(n)) return true;
  }
  return false;
}

/// MIME 是否在允许列表（大小写不敏感；空视为未知）。
bool isAllowedChatAttachmentMime(String? mime) {
  final m = (mime ?? '').trim().toLowerCase();
  if (m.isEmpty) return false;
  if (allowedChatAttachmentMimes.contains(m)) return true;
  // image/jpg → 已在集合；再容忍带参数
  final base = m.split(';').first.trim();
  return allowedChatAttachmentMimes.contains(base);
}

/// 从魔数嗅探常见图片 MIME；无法识别返回 null。
String? sniffImageMime(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'image/png';
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'image/webp';
  }
  return null;
}

/// 规范化 MIME：jpg → jpeg；未知且可嗅探则补全。
String? resolveChatAttachmentMime(Uint8List bytes, [String? declaredMime]) {
  final declared = (declaredMime ?? '').trim().toLowerCase().split(';').first;
  if (declared == 'image/jpg') return 'image/jpeg';
  if (isAllowedChatAttachmentMime(declared)) {
    return declared == 'image/jpg' ? 'image/jpeg' : declared;
  }
  final sniffed = sniffImageMime(bytes);
  if (sniffed != null && isAllowedChatAttachmentMime(sniffed)) {
    return sniffed;
  }
  return null;
}

/// 截断附件列表到 [maxChatAttachments]。
List<ImageRef> sanitizeChatAttachments(List<ImageRef> list) {
  if (list.length <= maxChatAttachments) {
    return List<ImageRef>.from(list);
  }
  return list.sublist(0, maxChatAttachments);
}

/// 校验单张附图；通过返回 null，否则返回中文错误。
String? validateChatAttachmentBytes(
  Uint8List bytes, {
  String? mime,
}) {
  if (bytes.isEmpty) return '图片内容为空';
  if (bytes.length > maxChatAttachmentBytes) {
    return '单张图片不能超过 4 MiB';
  }
  final resolved = resolveChatAttachmentMime(bytes, mime);
  if (resolved == null) {
    return '仅支持 PNG / JPEG / WebP 图片';
  }
  return null;
}
