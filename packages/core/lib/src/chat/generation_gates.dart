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

/// 对话发送门闩（CHAT-COMPOSER）。
bool canSendChatMessage({
  required GenerationRuntime generation,
  required String? activeSessionId,
  required bool hasConfiguredChatProvider,
}) {
  if (isGenerationBlocked(
    generation: generation,
    activeSessionId: activeSessionId,
  )) {
    return false;
  }
  return hasConfiguredChatProvider;
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
