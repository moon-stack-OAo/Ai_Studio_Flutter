import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('generation_gates', () {
    test('isGenerationBlocked：空闲为 false', () {
      final rt = GenerationRuntime();
      expect(
        isGenerationBlocked(generation: rt, activeSessionId: 's1'),
        isFalse,
      );
    });

    test('isGenerationBlocked：当前会话或其它 busy', () {
      final rt = GenerationRuntime();
      rt.begin('s1', () {});
      expect(
        isGenerationBlocked(generation: rt, activeSessionId: 's1'),
        isTrue,
      );
      expect(
        isGenerationBlocked(generation: rt, activeSessionId: 'other'),
        isTrue,
      );
    });

    test('canSendChatMessage', () {
      final rt = GenerationRuntime();
      expect(
        canSendChatMessage(
          generation: rt,
          activeSessionId: 's1',
          hasConfiguredChatProvider: true,
        ),
        isTrue,
      );
      expect(
        canSendChatMessage(
          generation: rt,
          activeSessionId: 's1',
          hasConfiguredChatProvider: false,
        ),
        isFalse,
      );
      rt.begin('s1', () {});
      expect(
        canSendChatMessage(
          generation: rt,
          activeSessionId: 's1',
          hasConfiguredChatProvider: true,
        ),
        isFalse,
      );
    });

    test('canGenerateImage 需非空 prompt', () {
      final rt = GenerationRuntime();
      expect(
        canGenerateImage(
          generation: rt,
          activeSessionId: 's1',
          hasConfiguredImageProvider: true,
          promptDraft: '  ',
        ),
        isFalse,
      );
      expect(
        canGenerateImage(
          generation: rt,
          activeSessionId: 's1',
          hasConfiguredImageProvider: true,
          promptDraft: '猫',
        ),
        isTrue,
      );
    });

    test('canGenerateVideo：参考图可空 prompt', () {
      final rt = GenerationRuntime();
      expect(
        canGenerateVideo(
          generation: rt,
          activeSessionId: 's1',
          hasConfiguredVideoProvider: true,
          promptDraft: '',
          hasReferenceImage: false,
        ),
        isFalse,
      );
      expect(
        canGenerateVideo(
          generation: rt,
          activeSessionId: 's1',
          hasConfiguredVideoProvider: true,
          promptDraft: '',
          hasReferenceImage: true,
        ),
        isTrue,
      );
    });

    test('跨模态互斥：对话 busy 阻断生图/生视频', () {
      final rt = GenerationRuntime();
      rt.begin('chat-1', () {});
      expect(
        canGenerateImage(
          generation: rt,
          activeSessionId: 'img-1',
          hasConfiguredImageProvider: true,
          promptDraft: '猫',
        ),
        isFalse,
      );
      expect(
        canGenerateVideo(
          generation: rt,
          activeSessionId: 'vid-1',
          hasConfiguredVideoProvider: true,
          promptDraft: '跑',
          hasReferenceImage: false,
        ),
        isFalse,
      );
    });

    test('跨模态互斥：生图 busy 阻断对话发送', () {
      final rt = GenerationRuntime();
      rt.begin('img-1', () {});
      expect(
        canSendChatMessage(
          generation: rt,
          activeSessionId: 'chat-1',
          hasConfiguredChatProvider: true,
        ),
        isFalse,
      );
    });
  });
}
