import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_material/pages/chat/chat_page.dart';
import 'package:mobile_material/pages/chat/widgets/composer.dart';
import 'package:mobile_material/pages/chat/widgets/message_list.dart';

void main() {
  testWidgets('正文更新保持 Scaffold/AppBar/Composer 身份；生成、会话和提供商变化正常响应', (
    tester,
  ) async {
    final providers = ProviderRepository(
      storage: MemoryProviderStorage(),
      connectionTester: StubProviderConnectionTester(),
    );
    final sessions = ChatSessionRepository(storage: MemoryChatSessionStorage());
    final defaults = ChatDefaultsRepository(
      storage: MemoryChatDefaultsStorage(),
    );
    final skills = SkillRepository(storage: MemorySkillStorage());
    final generation = GenerationRuntime();
    await Future.wait([
      providers.load(),
      sessions.load(),
      defaults.load(),
      skills.load(),
    ]);
    await providers.updateProvider(
      providers.activeProviderId,
      baseUrl: 'https://example.com/v1',
      apiKey: 'test',
      chatModel: 'gpt-4o',
    );
    final firstId = sessions.activeId;
    final assistant = (await sessions.appendMessage(
      firstId,
      role: ChatRole.assistant,
      content: '首段',
      streaming: true,
    ))!;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildMaterialLightTheme(),
        home: ChatPage(
          providerRepository: providers,
          sessionRepository: sessions,
          chatDefaultsRepository: defaults,
          skillRepository: skills,
          generation: generation,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    final composer = tester.widget<Composer>(find.byType(Composer));
    final list = tester.widget<MessageList>(find.byType(MessageList));
    for (var i = 0; i < 3; i++) {
      await sessions.updateMessage(
        firstId,
        assistant.id,
        content: '正文 $i',
        streaming: true,
        persist: false,
      );
      await tester.pump(const Duration(milliseconds: 70));
    }
    expect(
      identical(tester.widget(find.byType(Scaffold).first), scaffold),
      isTrue,
    );
    expect(identical(tester.widget(find.byType(AppBar)), appBar), isTrue);
    expect(identical(tester.widget(find.byType(Composer)), composer), isTrue);
    expect(identical(tester.widget(find.byType(MessageList)), list), isFalse);
    expect(
      tester
          .widget<MessageList>(find.byType(MessageList))
          .messages
          .last
          .content,
      '正文 2',
    );

    final token = generation.begin(firstId, () {});
    await tester.pump();
    expect(tester.widget<Composer>(find.byType(Composer)).streaming, isTrue);
    expect(
      tester.widget<MessageList>(find.byType(MessageList)).recallEnabled,
      isFalse,
    );
    expect(
      tester.widget<Composer>(find.byType(Composer)).onPickAttachments,
      isNull,
    );

    await sessions.createSession(title: '另一个会话');
    await tester.pump();
    expect(find.text('另一个会话'), findsOneWidget);
    expect(
      tester.widget<MessageList>(find.byType(MessageList)).messages,
      isEmpty,
    );
    expect(tester.widget<Composer>(find.byType(Composer)).streaming, isFalse);
    expect(tester.widget<Composer>(find.byType(Composer)).enabled, isFalse);
    generation.end(firstId, token);
    await tester.pump();
    expect(tester.widget<Composer>(find.byType(Composer)).enabled, isTrue);

    await sessions.setSessionOverrides(
      sessions.activeId,
      const ChatOverrides(systemPrompt: '新覆盖'),
    );
    await tester.pump();
    expect(find.byTooltip('会话参数（已覆盖）'), findsOneWidget);
    await sessions.setActive(firstId);
    await tester.pump();
    expect(
      tester.widget<MessageList>(find.byType(MessageList)).messages.last.id,
      assistant.id,
    );
    await providers.updateProvider(
      providers.activeProviderId,
      chatModel: 'text-only-model',
    );
    await tester.pump();
    expect(
      tester.widget<Composer>(find.byType(Composer)).visionSupported,
      isFalse,
    );
    expect(find.text('text-only-model'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    providers.dispose();
    defaults.dispose();
    skills.dispose();
    generation.dispose();
  });
}
