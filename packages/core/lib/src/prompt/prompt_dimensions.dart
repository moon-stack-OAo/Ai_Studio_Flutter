import 'prompt_presets.dart';

/// 维度选项（对齐现网 imageDimensions / videoDimensions）。
class PromptDimensionOption {
  const PromptDimensionOption({
    required this.id,
    required this.label,
    required this.text,
  });

  final String id;
  final String label;

  /// 拼入提示词的正文片段。
  final String text;
}

/// 维度分组。
class PromptDimensionGroup {
  const PromptDimensionGroup({
    required this.id,
    required this.label,
    required this.options,
    this.multiple = false,
  });

  final String id;
  final String label;
  final List<PromptDimensionOption> options;

  /// 是否多选；现网维度均为单选，保留字段以对齐 buildPrompt。
  final bool multiple;
}

/// 生图提示词维度（原文案对齐现网 imageDimensions.js）。
const List<PromptDimensionGroup> imagePromptDimensions = [
  PromptDimensionGroup(
    id: 'subject',
    label: '主体',
    options: [
      PromptDimensionOption(
        id: 'portrait',
        label: '人像',
        text: '人像作为画面主体',
      ),
      PromptDimensionOption(
        id: 'product',
        label: '产品静物',
        text: '产品静物置于画面中心',
      ),
      PromptDimensionOption(
        id: 'landscape',
        label: '风景',
        text: '自然风景作为主体',
      ),
      PromptDimensionOption(
        id: 'food',
        label: '美食',
        text: '美食特写作为主体',
      ),
      PromptDimensionOption(
        id: 'architecture',
        label: '建筑',
        text: '建筑空间作为主体',
      ),
      PromptDimensionOption(
        id: 'pet',
        label: '宠物',
        text: '宠物作为画面主体',
      ),
    ],
  ),
  PromptDimensionGroup(
    id: 'composition',
    label: '构图',
    options: [
      PromptDimensionOption(
        id: 'closeup',
        label: '居中特写',
        text: '居中特写构图',
      ),
      PromptDimensionOption(
        id: 'rule_of_thirds',
        label: '三分法',
        text: '三分法构图，主体偏置',
      ),
      PromptDimensionOption(
        id: 'wide',
        label: '广角全景',
        text: '广角全景构图',
      ),
      PromptDimensionOption(
        id: 'top_down',
        label: '俯拍',
        text: '俯拍视角构图',
      ),
    ],
  ),
  PromptDimensionGroup(
    id: 'lighting',
    label: '光影',
    options: [
      PromptDimensionOption(
        id: 'soft',
        label: '柔光',
        text: '柔和均匀光影',
      ),
      PromptDimensionOption(
        id: 'backlight',
        label: '逆光轮廓',
        text: '逆光勾勒轮廓光',
      ),
      PromptDimensionOption(
        id: 'neon',
        label: '霓虹',
        text: '霓虹灯光照明',
      ),
      PromptDimensionOption(
        id: 'natural',
        label: '自然光',
        text: '自然光洒落',
      ),
    ],
  ),
  PromptDimensionGroup(
    id: 'style',
    label: '风格',
    options: [
      PromptDimensionOption(
        id: 'photo',
        label: '写实摄影',
        text: '写实摄影风格',
      ),
      PromptDimensionOption(
        id: 'cinematic',
        label: '电影感',
        text: '电影感画面质感',
      ),
      PromptDimensionOption(
        id: 'illustration',
        label: '插画',
        text: '插画风格',
      ),
      PromptDimensionOption(
        id: 'cyberpunk',
        label: '赛博',
        text: '赛博朋克风格',
      ),
    ],
  ),
  PromptDimensionGroup(
    id: 'detail',
    label: '质感',
    options: [
      PromptDimensionOption(
        id: 'sharp',
        label: '锐利细节',
        text: '锐利清晰细节',
      ),
      PromptDimensionOption(
        id: 'bokeh',
        label: '浅景深',
        text: '浅景深虚化背景',
      ),
      PromptDimensionOption(
        id: 'film_grain',
        label: '胶片颗粒',
        text: '轻微胶片颗粒质感',
      ),
    ],
  ),
];

/// 视频提示词维度（原文案对齐现网 videoDimensions.js）。
const List<PromptDimensionGroup> videoPromptDimensions = [
  PromptDimensionGroup(
    id: 'subject',
    label: '主体',
    options: [
      PromptDimensionOption(
        id: 'person',
        label: '人物',
        text: '一位人物作为画面主体',
      ),
      PromptDimensionOption(
        id: 'product',
        label: '产品',
        text: '一件产品置于画面中心展示',
      ),
      PromptDimensionOption(
        id: 'landscape',
        label: '风景',
        text: '开阔自然风景作为主体',
      ),
      PromptDimensionOption(
        id: 'animal',
        label: '动物',
        text: '一只动物作为画面主体',
      ),
      PromptDimensionOption(
        id: 'street',
        label: '街景',
        text: '城市街景作为画面主体',
      ),
    ],
  ),
  PromptDimensionGroup(
    id: 'camera',
    label: '镜头',
    options: [
      PromptDimensionOption(
        id: 'dolly_in',
        label: '推进',
        text: '镜头缓慢向前推进',
      ),
      PromptDimensionOption(
        id: 'dolly_out',
        label: '拉远',
        text: '镜头平稳向后拉远',
      ),
      PromptDimensionOption(
        id: 'orbit',
        label: '环绕',
        text: '镜头绕主体缓慢环绕',
      ),
      PromptDimensionOption(
        id: 'follow',
        label: '跟随',
        text: '镜头从侧后方平稳跟随主体',
      ),
      PromptDimensionOption(
        id: 'aerial',
        label: '航拍',
        text: '航拍高机位俯瞰推进',
      ),
      PromptDimensionOption(
        id: 'static',
        label: '固定',
        text: '固定机位稳定构图',
      ),
    ],
  ),
  PromptDimensionGroup(
    id: 'motion',
    label: '运动',
    options: [
      PromptDimensionOption(
        id: 'smooth',
        label: '缓慢流畅',
        text: '运动节奏缓慢流畅',
      ),
      PromptDimensionOption(
        id: 'slow_mo',
        label: '慢动作',
        text: '慢动作呈现细腻动态',
      ),
      PromptDimensionOption(
        id: 'urgent',
        label: '急促',
        text: '运动节奏急促有力',
      ),
      PromptDimensionOption(
        id: 'float',
        label: '漂浮感',
        text: '画面带有轻盈漂浮感',
      ),
    ],
  ),
  PromptDimensionGroup(
    id: 'style',
    label: '风格',
    options: [
      PromptDimensionOption(
        id: 'cinematic',
        label: '电影感',
        text: '电影级质感与运镜',
      ),
      PromptDimensionOption(
        id: 'realistic',
        label: '写实',
        text: '写实摄影风格',
      ),
      PromptDimensionOption(
        id: 'cyberpunk',
        label: '赛博朋克',
        text: '赛博朋克科幻风格',
      ),
      PromptDimensionOption(
        id: 'anime',
        label: '动画感',
        text: '动画感画面风格',
      ),
    ],
  ),
  PromptDimensionGroup(
    id: 'mood',
    label: '氛围',
    options: [
      PromptDimensionOption(
        id: 'dusk',
        label: '黄昏',
        text: '黄昏暖色柔光氛围',
      ),
      PromptDimensionOption(
        id: 'rain_night',
        label: '雨夜',
        text: '雨夜潮湿冷暖对比光',
      ),
      PromptDimensionOption(
        id: 'neon',
        label: '霓虹',
        text: '霓虹灯光与都市夜色',
      ),
      PromptDimensionOption(
        id: 'sunny',
        label: '晴朗自然光',
        text: '晴朗自然光，氛围清新',
      ),
    ],
  ),
];

/// 按领域取维度分组。
List<PromptDimensionGroup> getPromptDimensions(PromptDomain domain) {
  return switch (domain) {
    PromptDomain.image => imagePromptDimensions,
    PromptDomain.video => videoPromptDimensions,
  };
}
