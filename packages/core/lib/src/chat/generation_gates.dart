import 'generation_runtime.dart';

/// 全局生成门闩：当前会话正在生成，或其它能力占用 [GenerationRuntime]。
bool isGenerationBlocked({
  required GenerationRuntime generation,
  required String? activeSessionId,
}) {
  if (generation.isCurrent(activeSessionId)) return true;
  if (generation.busy) return true;
  return false;
}

/// 对话发送门闩（CHAT-COMPOSER / CHAT-ATTACH）。
///
/// [textDraft] 为 null 时不校验正文（兼容仅查提供商/忙态的旧调用）。
/// 传入非 null 时：有 [hasAttachments] 可空文，否则需 trim 非空。
bool canSendChatMessage({
  required GenerationRuntime generation,
  required String? activeSessionId,
  required bool hasConfiguredChatProvider,
  String? textDraft,
  bool hasAttachments = false,
}) {
  if (isGenerationBlocked(
    generation: generation,
    activeSessionId: activeSessionId,
  )) {
    return false;
  }
  if (!hasConfiguredChatProvider) return false;
  if (textDraft == null) return true;
  if (hasAttachments) return true;
  return textDraft.trim().isNotEmpty;
}

/// 生图发送门闩（需非空 prompt）。
bool canGenerateImage({
  required GenerationRuntime generation,
  required String? activeSessionId,
  required bool hasConfiguredImageProvider,
  required String promptDraft,
}) {
  if (isGenerationBlocked(
    generation: generation,
    activeSessionId: activeSessionId,
  )) {
    return false;
  }
  if (!hasConfiguredImageProvider) return false;
  return promptDraft.trim().isNotEmpty;
}

/// 生视频发送门闩：有参考图即可，否则需非空 prompt。
bool canGenerateVideo({
  required GenerationRuntime generation,
  required String? activeSessionId,
  required bool hasConfiguredVideoProvider,
  required String promptDraft,
  required bool hasReferenceImage,
}) {
  if (isGenerationBlocked(
    generation: generation,
    activeSessionId: activeSessionId,
  )) {
    return false;
  }
  if (!hasConfiguredVideoProvider) return false;
  if (hasReferenceImage) return true;
  return promptDraft.trim().isNotEmpty;
}
