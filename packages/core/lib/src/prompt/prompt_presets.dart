import 'dart:math';

/// 提示词预设领域。
enum PromptDomain {
  image,
  video,
}

/// 单条本地提示词预设（对齐现网 PromptAssist 模板，不接大模型）。
class PromptPreset {
  const PromptPreset({
    required this.id,
    required this.label,
    required this.prompt,
    this.mode,
    this.tags = const [],
  });

  final String id;
  final String label;
  final String prompt;

  /// 文生/图生模式过滤；`null` 表示通用。
  final String? mode;
  final List<String> tags;
}

const List<PromptPreset> imagePromptPresets = [
  PromptPreset(
    id: 'i-t2i-portrait',
    label: '人像写真',
    mode: 'txt2img',
    prompt:
        '一位东亚女性半身肖像，自然侧光从窗边洒落，浅景深虚化背景，细腻皮肤质感，柔和眼神，85mm 镜头感，写实摄影风格',
    tags: ['人像', '写实', '侧光'],
  ),
  PromptPreset(
    id: 'i-t2i-product',
    label: '产品静物',
    mode: 'txt2img',
    prompt:
        '极简产品静物摄影，哑光陶瓷水杯置于浅灰台面，柔光箱均匀照明，干净构图留白，突出材质与阴影层次，商业广告质感',
    tags: ['产品', '静物', '商业'],
  ),
  PromptPreset(
    id: 'i-t2i-landscape',
    label: '风景大片',
    mode: 'txt2img',
    prompt:
        '高山湖泊日出风景，金色晨光映照水面与云层，广角构图前景有礁石，中景湖面，远山层叠，清透空气感，风光摄影风格',
    tags: ['风景', '自然光', '广角'],
  ),
  PromptPreset(
    id: 'i-t2i-cyber',
    label: '赛博都市',
    mode: 'txt2img',
    prompt:
        '赛博朋克雨夜街景，霓虹招牌与全息广告倒映在湿润地面，高对比粉紫青蓝光，蒸汽与雾气，低角度构图，科幻概念艺术',
    tags: ['赛博', '夜景', '概念'],
  ),
  PromptPreset(
    id: 'i-t2i-food',
    label: '美食特写',
    mode: 'txt2img',
    prompt: '新鲜草莓塔微距特写，奶油与果肉质感清晰，柔和顶侧光，浅景深，暖色调，食物摄影风格，诱人细节',
    tags: ['美食', '微距', '静物'],
  ),
  PromptPreset(
    id: 'i-t2i-arch',
    label: '建筑空间',
    mode: 'txt2img',
    prompt:
        '现代极简建筑外立面，混凝土与玻璃材质对比，对称构图，硬朗几何线条，午后斜射光形成清晰阴影，建筑摄影风格',
    tags: ['建筑', '几何', '光影'],
  ),
  PromptPreset(
    id: 'i-t2i-pet',
    label: '宠物写真',
    mode: 'txt2img',
    prompt: '一只橘猫趴在阳光窗台，逆光勾勒毛发轮廓，眼神对焦清晰，浅景深，温馨居家氛围，写实宠物摄影',
    tags: ['宠物', '逆光', '写实'],
  ),
  PromptPreset(
    id: 'i-t2i-illustration',
    label: '插画风格',
    mode: 'txt2img',
    prompt:
        '日系清新插画风少女坐在樱花树下，柔和粉彩配色，干净线条，扁平与轻微阴影结合，治愈氛围，二次元插画风格',
    tags: ['插画', '日系', '治愈'],
  ),
  PromptPreset(
    id: 'i-i2i-style',
    label: '风格迁移',
    mode: 'img2img',
    prompt: '在参考图基础上转换为油画质感，保留主体构图与姿态，强化笔触与色彩层次，艺术氛围',
    tags: ['风格', '油画'],
  ),
  PromptPreset(
    id: 'i-i2i-detail',
    label: '细节增强',
    mode: 'img2img',
    prompt: '在参考图基础上增强纹理与细节清晰度，保留原有构图与色调，材质更真实，边缘更锐利',
    tags: ['细节', '增强'],
  ),
  PromptPreset(
    id: 'i-i2i-bg',
    label: '换背景',
    mode: 'img2img',
    prompt: '在参考图基础上保留主体，将背景替换为柔和虚化的城市夜景，光影与主体自然衔接',
    tags: ['背景', '替换'],
  ),
  PromptPreset(
    id: 'i-i2i-light',
    label: '光影重塑',
    mode: 'img2img',
    prompt: '在参考图基础上重塑光影，改为侧逆光轮廓光，加深阴影层次，提升立体感与氛围，主体不变',
    tags: ['光影', '重塑'],
  ),
  PromptPreset(
    id: 'i-common-clean',
    label: '干净构图',
    prompt: '干净简洁构图，主体突出，柔和自然光，高品质细节，无杂乱元素',
    tags: ['通用', '构图'],
  ),
];

const List<PromptPreset> videoPromptPresets = [
  PromptPreset(
    id: 'v-t2v-walk',
    label: '人物走路',
    mode: 'txt2video',
    prompt:
        '一位年轻女性穿着风衣在秋日林荫道上缓步前行，落叶随风轻扬，跟拍镜头平稳跟随，浅景深虚化背景，暖色柔光从侧面洒落，氛围宁静自然',
    tags: ['人物', '跟拍', '自然光'],
  ),
  PromptPreset(
    id: 'v-t2v-product',
    label: '产品旋转',
    mode: 'txt2video',
    prompt:
        '一款哑光黑无线耳机置于纯白台面上缓慢水平旋转展示，特写镜头固定构图，均匀柔光箱照明，突出材质纹理与金属细节，干净商业广告风格',
    tags: ['产品', '旋转', '商业'],
  ),
  PromptPreset(
    id: 'v-t2v-aerial',
    label: '航拍风景',
    mode: 'txt2video',
    prompt:
        '航拍镜头从高空缓缓向前推进掠过翠绿山谷与蜿蜒河流，晨雾在山间流动，广角镜头，金色晨光穿透云层，壮阔空灵感',
    tags: ['航拍', '风景', '推进'],
  ),
  PromptPreset(
    id: 'v-t2v-cyber',
    label: '赛博夜景',
    mode: 'txt2video',
    prompt:
        '赛博朋克都市夜景，霓虹招牌与全息广告在雨后湿润街道上倒映，低角度缓慢横移镜头，粉紫青蓝对比光，潮湿雾气与蒸汽，未来科幻氛围',
    tags: ['赛博', '夜景', '横移'],
  ),
  PromptPreset(
    id: 'v-t2v-rain',
    label: '雨夜街道',
    mode: 'txt2video',
    prompt:
        '雨夜空旷街道，路灯在积水中拉出长长光晕，行人撑伞快步走过，固定机位轻微推近，高对比冷暖光，潮湿空气与水雾，孤独电影感',
    tags: ['雨夜', '街道', '电影感'],
  ),
  PromptPreset(
    id: 'v-t2v-animal',
    label: '动物奔跑',
    mode: 'txt2video',
    prompt:
        '一只金毛犬在开阔草原上全力奔跑，侧向跟拍镜头保持同步，鬃毛与草地被风吹起，明亮自然光，景深浅焦，充满速度与活力',
    tags: ['动物', '跟拍', '运动'],
  ),
  PromptPreset(
    id: 'v-t2v-latte',
    label: '咖啡拉花',
    mode: 'txt2video',
    prompt:
        '极近特写咖啡拉花过程，牛奶缓缓注入形成心形图案，微距镜头轻微下移，柔和顶光，蒸汽升腾，温馨生活感与细腻质感',
    tags: ['特写', '美食', '微距'],
  ),
  PromptPreset(
    id: 'v-t2v-timelapse',
    label: '城市延时',
    mode: 'txt2video',
    prompt:
        '城市天际线从黄昏到夜晚的延时摄影，车流光轨在道路上流动，云层快速掠过，固定广角高机位，暖橙转深蓝的色温变化，都市节奏感',
    tags: ['延时', '城市', '夜景'],
  ),
  PromptPreset(
    id: 'v-i2v-dolly',
    label: '缓慢推进',
    mode: 'img2video',
    prompt: '基于参考图，镜头缓慢平稳向前推进，轻微景深变化，保持主体与构图不变，自然光影过渡',
    tags: ['推进', '镜头运动'],
  ),
  PromptPreset(
    id: 'v-i2v-orbit',
    label: '环绕运镜',
    mode: 'img2video',
    prompt: '基于参考图，镜头绕主体缓慢环绕半圈，视角平滑切换，主体位置居中稳定，光影随角度轻微变化',
    tags: ['环绕', '镜头运动'],
  ),
  PromptPreset(
    id: 'v-i2v-follow',
    label: '跟随运镜',
    mode: 'img2video',
    prompt: '基于参考图，镜头从侧后方轻微跟随主体向前移动，保持构图稳定，背景产生自然运动视差',
    tags: ['跟随', '镜头运动'],
  ),
  PromptPreset(
    id: 'v-i2v-parallax',
    label: '轻微视差',
    mode: 'img2video',
    prompt: '基于参考图，镜头做轻微左右平移，前景与背景产生细腻视差层次，主体相对静止，氛围沉静',
    tags: ['视差', '平移'],
  ),
  PromptPreset(
    id: 'v-i2v-crane',
    label: '镜头上移',
    mode: 'img2video',
    prompt: '基于参考图，镜头缓慢向上升起，逐渐展现场景纵深，保持画面稳定，光影自然连贯',
    tags: ['升镜', '镜头运动'],
  ),
  PromptPreset(
    id: 'v-i2v-bokeh',
    label: '景深呼吸',
    mode: 'img2video',
    prompt: '基于参考图，焦点在主体与背景之间缓慢呼吸切换，浅景深虚实交替，画面几乎无位移，柔和电影感',
    tags: ['景深', '焦点'],
  ),
  PromptPreset(
    id: 'v-common-cinematic',
    label: '电影运镜',
    prompt: '电影级运镜，平滑稳定，自然光影过渡，浅景深，氛围沉浸，画面干净无抖动',
    tags: ['通用', '电影感'],
  ),
];

List<PromptPreset> getPromptPresets(
  PromptDomain domain, {
  String? mode,
}) {
  final list = switch (domain) {
    PromptDomain.image => imagePromptPresets,
    PromptDomain.video => videoPromptPresets,
  };
  if (mode == null || mode.isEmpty) return List<PromptPreset>.from(list);
  return list
      .where((e) => e.mode == null || e.mode == mode)
      .toList(growable: false);
}

PromptPreset? pickRandomPromptPreset(
  PromptDomain domain, {
  String? mode,
  Random? random,
}) {
  final list = getPromptPresets(domain, mode: mode);
  if (list.isEmpty) return null;
  final rng = random ?? Random();
  return list[rng.nextInt(list.length)];
}
