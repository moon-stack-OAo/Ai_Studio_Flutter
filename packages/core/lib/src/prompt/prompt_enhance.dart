import 'package:http/http.dart' as http;

import '../chat/chat_errors.dart';
import '../openai/chat_client.dart';
import '../provider/provider_repository.dart';
import 'prompt_enhance_skills.dart';
import 'prompt_presets.dart';

export 'prompt_enhance_skills.dart';

/// 图像润色基座 system（保真、结构、密度、语言、长度、纯正文输出）。
const String enhanceSystemImage =
    '你是专业的图像生成提示词优化助手。\n'
    '保真：不改主体、事件与关键专有名词；用户已写细节优先，勿覆盖或删除。\n'
    '结构：按「主体 → 场景 → 构图 → 光影/材质 → 风格」补全缺失项；已有项保持。\n'
    '密度：禁止空洞堆砌（如 masterpiece、best quality、8k、ultra detailed、cinematic 等无信息词）。\n'
    '语言：跟随用户输入语言；中英混写不强行全译。\n'
    '长度：标准约中文 80–250 字或英文 40–120 词（精简风格取下限，电影感可略长）。\n'
    '输出：只输出优化后提示词正文；不要解释、标题、前后缀、markdown；不要 Negative prompt 段。\n'
    '示例：\n'
    '短输入：雨夜街头的猫\n'
    '好输出：雨夜湿润柏油路，一只毛色斑驳的橘猫蹲在霓虹灯牌下，侧光映出水洼倒影，'
    '中景略俯，浅景深，沥青反光与细雨丝清晰可辨';

/// 视频润色基座 system（在图像结构上增加镜头运动/节奏）。
const String enhanceSystemVideo =
    '你是专业的视频生成提示词优化助手。\n'
    '保真：不改主体、事件与关键专有名词；用户已写细节优先，勿覆盖或删除。\n'
    '结构：按「主体 → 场景 → 构图 → 光影/材质 → 风格 → 镜头运动/节奏」补全缺失项；已有项保持。\n'
    '密度：禁止空洞堆砌（如 masterpiece、best quality、8k、ultra detailed、cinematic 等无信息词）。\n'
    '语言：跟随用户输入语言；中英混写不强行全译。\n'
    '长度：标准约中文 80–250 字或英文 40–120 词（精简风格取下限，电影感可略长）。\n'
    '输出：只输出优化后提示词正文；不要解释、标题、前后缀、markdown；不要 Negative prompt 段。\n'
    '示例：\n'
    '短输入：海边日落行人\n'
    '好输出：金色落日下的海岸线，一位穿浅色风衣的行人沿潮线缓步前行，'
    '镜头缓慢横移跟随，浪花轻拍脚踝，暖色侧逆光勾勒轮廓，节奏舒缓、结尾定格远景';

const Map<String, String> _modeHints = {
  'txt2img':
      '当前为文生图：仅依据文字描述优化；不要假设存在参考图；侧重可绘制的视觉要素与结构完整。',
  'txt2video':
      '当前为文生视频：仅依据文字描述优化；不要假设存在参考图；侧重可拍摄的动态、镜头运动与时间节奏。',
  'img2video':
      '当前为图生视频：请基于参考图主体进行优化，不要推翻或替换主体，侧重镜头运动、动态与节奏描述。',
  'img2img':
      '当前为图生图：请基于参考图主体进行优化，不要推翻或替换主体，侧重改动方向、风格与细节描述。',
};

/// 解析润色用 system prompt = 基座 + modeHint + skill.systemExtra。
///
/// [skill] / [skillId] 未传时使用默认 [defaultPromptEnhanceSkill]（balanced）。
String resolveEnhanceSystemPrompt(
  PromptDomain domain,
  String? mode, {
  PromptEnhanceSkill? skill,
  String? skillId,
}) {
  final base =
      domain == PromptDomain.image ? enhanceSystemImage : enhanceSystemVideo;
  final resolved = resolvePromptEnhanceSkill(skill: skill, skillId: skillId);
  final hint = mode == null || mode.isEmpty ? null : _modeHints[mode];
  final parts = <String>[base];
  if (hint != null) parts.add(hint);
  parts.add(resolved.systemExtra);
  return parts.join('\n');
}

/// 剥离模型可能包上的引号或 markdown 代码块。
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

int _clampEnhanceMaxTokens(int value) {
  if (value <= 0) return defaultEnhanceMaxTokens;
  return value > defaultEnhanceMaxTokens ? defaultEnhanceMaxTokens : value;
}

/// 用当前对话模型润色生图/生视频提示词。
///
/// - 未传 [skill]/[skillId] 时用 balanced。
/// - [temperature] 若调用方显式传入则优先生效，否则用 skill 的。
/// - 取消流式时由上层清空润色结果（本 API 抛 [ChatAbortException]；UI 负责清空）。
/// - 换风格后再跑：传入当前润色结果作为 [text] 即可（UI 后做）。
Future<String> enhancePrompt({
  required String text,
  required PromptDomain domain,
  String? mode,
  PromptEnhanceSkill? skill,
  String? skillId,
  required ActiveChatCredentials credentials,
  required OpenAiCompatibleChatClient chatClient,
  double? temperature,
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

  final resolvedSkill =
      resolvePromptEnhanceSkill(skill: skill, skillId: skillId);
  final resolvedMode = mode?.trim() ?? '';
  final system = resolveEnhanceSystemPrompt(
    domain,
    resolvedMode.isEmpty ? null : resolvedMode,
    skill: resolvedSkill,
  );
  final userContent =
      resolvedMode.isNotEmpty && _modeHints.containsKey(resolvedMode)
          ? '$trimmed\n\n（模式：$resolvedMode）'
          : trimmed;

  final effectiveTemp = temperature ?? resolvedSkill.temperature;
  final effectiveMaxTokens = _clampEnhanceMaxTokens(resolvedSkill.maxTokens);

  final raw = await chatClient.streamChatWithCredentials(
    credentials,
    messages: [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': userContent},
    ],
    temperature: effectiveTemp,
    maxTokens: effectiveMaxTokens,
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

/// 基于上一版润色结果，按用户指令再改一版（供后续 B2 / 换风格续跑）。
///
/// [previous] 为当前润色正文；[instruction] 为改写要求（可为空，则等同再润色一次）。
Future<String> refineEnhancedPrompt({
  required String previous,
  String instruction = '',
  required PromptDomain domain,
  String? mode,
  PromptEnhanceSkill? skill,
  String? skillId,
  required ActiveChatCredentials credentials,
  required OpenAiCompatibleChatClient chatClient,
  double? temperature,
  Duration? timeout,
  http.Client? client,
  void Function(String delta, String fullText)? onDelta,
}) async {
  final base = previous.trim();
  if (base.isEmpty) {
    throw const ChatApiException('请先完成一次润色再继续修改');
  }
  final tip = instruction.trim();
  final text = tip.isEmpty
      ? base
      : '上一版润色结果：\n$base\n\n请按以下要求修改（仍只输出提示词正文）：\n$tip';
  return enhancePrompt(
    text: text,
    domain: domain,
    mode: mode,
    skill: skill,
    skillId: skillId,
    credentials: credentials,
    chatClient: chatClient,
    temperature: temperature,
    timeout: timeout,
    client: client,
    onDelta: onDelta,
  );
}
