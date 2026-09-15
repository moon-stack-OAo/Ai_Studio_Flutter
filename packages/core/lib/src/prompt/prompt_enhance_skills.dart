/// 提示词润色默认采样温度（与聊天 [defaultChatTemperature] 拆开）。
const double defaultEnhanceTemperature = 0.4;

/// 润色默认 max_tokens 上限。
const int defaultEnhanceMaxTokens = 2048;

/// 内置润色风格（UI 文案用「润色风格」；id 英文、label 中文）。
class PromptEnhanceSkill {
  const PromptEnhanceSkill({
    required this.id,
    required this.label,
    required this.systemExtra,
    this.temperature = defaultEnhanceTemperature,
    this.maxTokens = defaultEnhanceMaxTokens,
  });

  final String id;
  final String label;

  /// 追加到基座 system 后的风格说明。
  final String systemExtra;

  /// 本风格默认温度；调用方显式传入 temperature 时优先生效。
  final double temperature;

  /// 本风格默认 max_tokens（仍应 ≤ [defaultEnhanceMaxTokens]）。
  final int maxTokens;
}

/// 均衡：默认；补全细节不过度加戏。
const PromptEnhanceSkill promptEnhanceSkillBalanced = PromptEnhanceSkill(
  id: 'balanced',
  label: '均衡',
  systemExtra:
      '润色风格=均衡：在忠实原意前提下适度补全缺失的结构要素与可感知细节；'
      '不要额外编造剧情、角色关系或未提及的道具；密度适中。',
  temperature: defaultEnhanceTemperature,
  maxTokens: 1024,
);

/// 精简：更短、高密度。
const PromptEnhanceSkill promptEnhanceSkillConcise = PromptEnhanceSkill(
  id: 'concise',
  label: '精简',
  systemExtra:
      '润色风格=精简：输出更短、信息密度更高；删去重复与空泛修饰；'
      '优先保留主体、关键动作/场景与最必要的光影或材质词；标准长度取下限附近。',
  temperature: 0.3,
  maxTokens: 512,
);

/// 电影感：镜头/光影/氛围加强。
const PromptEnhanceSkill promptEnhanceSkillCinematic = PromptEnhanceSkill(
  id: 'cinematic',
  label: '电影感',
  systemExtra:
      '润色风格=电影感：在不改主体与事件的前提下，加强镜头语言、光影层次与氛围情绪；'
      '可用景别、运镜、色调与空气感等具体描述，避免空洞的 cinematic/masterpiece 堆砌。',
  temperature: 0.45,
  maxTokens: 1536,
);

/// 写实：摄影向镜头/光照/材质。
const PromptEnhanceSkill promptEnhanceSkillPhotoreal = PromptEnhanceSkill(
  id: 'photoreal',
  label: '写实',
  systemExtra:
      '润色风格=写实：偏摄影/纪实表达；补全镜头焦段或景深感、自然光照方向与材质质感；'
      '避免插画风、二次元或超现实夸张，除非用户原文已明确要求。',
  temperature: 0.35,
  maxTokens: 1024,
);

/// 保真润色：几乎只理顺，少加新元素。
const PromptEnhanceSkill promptEnhanceSkillPreserve = PromptEnhanceSkill(
  id: 'preserve',
  label: '保真润色',
  systemExtra:
      '润色风格=保真润色：几乎只做语序理顺、标点与同义改写；'
      '禁止新增未出现的物体、场景、风格标签或镜头术语；长度与原文接近。',
  temperature: 0.25,
  maxTokens: 768,
);

/// 全部内置润色风格（顺序即 UI 建议展示顺序）。
const List<PromptEnhanceSkill> promptEnhanceSkills = [
  promptEnhanceSkillBalanced,
  promptEnhanceSkillConcise,
  promptEnhanceSkillCinematic,
  promptEnhanceSkillPhotoreal,
  promptEnhanceSkillPreserve,
];

/// 默认润色风格。
const PromptEnhanceSkill defaultPromptEnhanceSkill = promptEnhanceSkillBalanced;

/// 按 id 查找内置风格；未知 id 返回 null。
PromptEnhanceSkill? promptEnhanceSkillById(String? id) {
  final key = id?.trim() ?? '';
  if (key.isEmpty) return null;
  for (final s in promptEnhanceSkills) {
    if (s.id == key) return s;
  }
  return null;
}

/// 解析最终使用的风格：显式 [skill] > [skillId] > 默认 balanced。
PromptEnhanceSkill resolvePromptEnhanceSkill({
  PromptEnhanceSkill? skill,
  String? skillId,
}) {
  if (skill != null) return skill;
  return promptEnhanceSkillById(skillId) ?? defaultPromptEnhanceSkill;
}
