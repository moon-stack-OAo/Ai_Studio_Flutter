import 'package:http/http.dart' as http;

import '../chat/chat_errors.dart';
import '../openai/chat_client.dart';
import '../provider/provider_repository.dart';
import 'prompt_presets.dart';

/// 对齐现网 `enhancePrompt.js` 的 system prompt（图像）。
const String enhanceSystemImage =
    '你是专业的图像生成提示词优化助手。'
    '在保留用户核心意图的前提下，补全并强化：构图、光影、材质、风格与画面细节。'
    '只输出优化后的提示词正文，不要解释、不要标题、不要前后缀、不要 markdown。';

/// 对齐现网 `enhancePrompt.js` 的 system prompt（视频）。
const String enhanceSystemVideo =
    '你是专业的视频生成提示词优化助手。'
    '在保留用户核心意图的前提下，补全并强化：主体、镜头运动、节奏、光影、氛围与画面细节。'
    '只输出优化后的提示词正文，不要解释、不要标题、不要前后缀、不要 markdown。';

const Map<String, String> _modeHints = {
  'img2video':
      '当前为图生视频：请基于参考图主体进行优化，不要推翻或替换主体，侧重镜头运动、动态与节奏描述。',
  'img2img':
      '当前为图生图：请基于参考图主体进行优化，不要推翻或替换主体，侧重改动方向、风格与细节描述。',
};

/// 解析润色用 system prompt（对齐现网 `resolveSystemPrompt`）。
String resolveEnhanceSystemPrompt(PromptDomain domain, [String? mode]) {
  final base =
      domain == PromptDomain.image ? enhanceSystemImage : enhanceSystemVideo;
  final hint = mode == null || mode.isEmpty ? null : _modeHints[mode];
  return hint == null ? base : '$base\n$hint';
}

/// 剥离模型可能包上的引号或 markdown 代码块（对齐现网 `stripEnhancedPrompt`）。
String stripEnhancedPrompt(String? raw) {
  var text = (raw ?? '').trim();
  if (text.isEmpty) return '';

  final fence = RegExp(
    r'^```(?:\w+)?\s*\n?([\s\S]*?)\n?```$',
    unicode: true,
  ).firstMatch(text);
  if (fence != null) {
    text = (fence.group(1) ?? '').trim();
  }

  if ((text.startsWith('"') && text.endsWith('"')) ||
      (text.startsWith("'") && text.endsWith("'")) ||
      (text.startsWith('“') && text.endsWith('”')) ||
      (text.startsWith('「') && text.endsWith('」'))) {
    text = text.substring(1, text.length - 1).trim();
  }

  return text;
}

/// 用当前对话模型润色生图/生视频提示词（对齐现网 `enhancePrompt`）。
///
/// 走 [OpenAiCompatibleChatClient] 流式通路并聚合全文；失败抛出可读中文异常。
Future<String> enhancePrompt({
  required String text,
  required PromptDomain domain,
  String? mode,
  required ActiveChatCredentials credentials,
  required OpenAiCompatibleChatClient chatClient,
  double temperature = defaultChatTemperature,
  Duration? timeout,
  http.Client? client,
  void Function(String delta, String fullText)? onDelta,
}) async {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    throw const ChatApiException('请先输入或填入提示词再优化');
  }
  if (credentials.chatModel.trim().isEmpty) {
    throw const ChatApiException('请先在设置中配置对话模型');
  }
  if (credentials.apiKey.trim().isEmpty) {
    throw const ChatApiException('请先配置提供商与 API Key');
  }

  final resolvedMode = mode?.trim() ?? '';
  final system = resolveEnhanceSystemPrompt(
    domain,
    resolvedMode.isEmpty ? null : resolvedMode,
  );
  final userContent = resolvedMode.isNotEmpty && _modeHints.containsKey(resolvedMode)
      ? '$trimmed\n\n（模式：$resolvedMode）'
      : trimmed;

  final raw = await chatClient.streamChatWithCredentials(
    credentials,
    messages: [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': userContent},
    ],
    temperature: temperature,
    // 提示词优化无需长文，限制输出降低挂起与超时概率（对齐现网 max_tokens: 2048）
    maxTokens: 2048,
    timeout: timeout,
    client: client,
    onDelta: onDelta,
  );

  final content = stripEnhancedPrompt(raw);
  if (content.isEmpty) {
    throw const ChatApiException('优化结果为空，请重试');
  }
  return content;
}
