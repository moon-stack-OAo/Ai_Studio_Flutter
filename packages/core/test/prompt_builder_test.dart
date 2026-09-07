import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('空选中 → 空字符串', () {
    expect(buildPromptFromSelection(PromptDomain.image, {}), '');
    expect(buildPromptFromSelection(PromptDomain.video, {}), '');

    final state = PromptBuilderState(PromptDomain.image);
    expect(state.preview, '');
    expect(state.build(), '');
  });

  test('单选多项拼接顺序与维度顺序一致（image）', () {
    final selection = <String, Object?>{
      'detail': 'sharp',
      'subject': 'portrait',
      'style': 'photo',
      'lighting': 'soft',
      'composition': 'closeup',
    };
    expect(
      buildPromptFromSelection(PromptDomain.image, selection),
      '人像作为画面主体，居中特写构图，柔和均匀光影，写实摄影风格，锐利清晰细节',
    );
  });

  test('toggle 取消', () {
    final state = PromptBuilderState(PromptDomain.image);
    state.toggleOption('subject', 'portrait');
    expect(state.selection['subject'], 'portrait');
    expect(state.preview, '人像作为画面主体');

    state.toggleOption('subject', 'portrait');
    expect(state.selection['subject'], isNull);
    expect(state.preview, '');
  });

  test('extraText 追加', () {
    final selection = <String, Object?>{'subject': 'food'};
    expect(
      buildPromptFromSelection(
        PromptDomain.image,
        selection,
        extraText: '暖色调',
      ),
      '美食特写作为主体，暖色调',
    );

    final state = PromptBuilderState(PromptDomain.image);
    state.setOption('subject', 'food');
    expect(state.build('暖色调'), '美食特写作为主体，暖色调');
  });

  test('video 维度拼装一例', () {
    final selection = <String, Object?>{
      'subject': 'person',
      'camera': 'dolly_in',
      'motion': 'smooth',
      'style': 'cinematic',
      'mood': 'dusk',
    };
    expect(
      buildPromptFromSelection(PromptDomain.video, selection),
      '一位人物作为画面主体，镜头缓慢向前推进，运动节奏缓慢流畅，电影级质感与运镜，黄昏暖色柔光氛围',
    );
  });

  test('clear 重置选中', () {
    final state = PromptBuilderState(PromptDomain.video);
    state.toggleOption('subject', 'animal');
    state.toggleOption('camera', 'orbit');
    expect(state.preview, isNotEmpty);
    state.clear();
    expect(state.preview, '');
    expect(state.selection['subject'], isNull);
  });
}
