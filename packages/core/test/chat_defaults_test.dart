import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('ChatDefaults JSON roundtrip', () {
    const original = ChatDefaults(
      temperature: 1.2,
      systemPrompt: '你是助手',
      maxTokens: 2048,
      apiTimeoutMs: 120000,
      contextTrimEnabled: false,
      contextMaxTurns: 8,
      contextMaxCharsEnabled: true,
      contextMaxChars: 16000,
    );
    final restored = ChatDefaults.fromJson(original.toJson());
    expect(restored, original);
  });

  test('sanitized clamps out-of-range', () {
    final bad = const ChatDefaults(
      temperature: 9,
      maxTokens: -3,
      apiTimeoutMs: 10,
      contextMaxTurns: 0,
      contextMaxChars: 0,
    ).sanitized();
    expect(bad.temperature, 2.0);
    expect(bad.maxTokens, 0);
    expect(bad.apiTimeoutMs, 1000);
    expect(bad.contextMaxTurns, 1);
    expect(bad.contextMaxChars, 1);
  });

  test('MemoryChatDefaultsStorage roundtrip via repository', () async {
    final storage = MemoryChatDefaultsStorage();
    final repo = ChatDefaultsRepository(storage: storage);
    await repo.load();
    expect(repo.defaults.temperature, defaultChatTemperature);

    await repo.update(
      temperature: 0.3,
      systemPrompt: 'sys',
      maxTokens: 512,
      apiTimeoutMs: 90000,
      contextTrimEnabled: true,
      contextMaxTurns: 12,
      contextMaxCharsEnabled: true,
      contextMaxChars: 8000,
    );
    expect(repo.defaults.temperature, 0.3);
    expect(repo.defaults.systemPrompt, 'sys');
    expect(storage.current.maxTokens, 512);

    final other = ChatDefaultsRepository(storage: storage);
    await other.load();
    expect(other.defaults, repo.defaults);

    await other.resetToRecommended();
    expect(other.defaults, ChatDefaults.recommended);
  });

  test('PrefsChatDefaultsStorage roundtrip with injected prefs', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = PrefsChatDefaultsStorage(prefs: prefs);
    await storage.save(
      const ChatDefaults(
        temperature: 0.55,
        systemPrompt: 'prefs',
        maxTokens: 100,
      ),
    );
    final loaded = await storage.load();
    expect(loaded.temperature, 0.55);
    expect(loaded.systemPrompt, 'prefs');
    expect(loaded.maxTokens, 100);
    expect(prefs.getString(PrefsChatDefaultsStorage.prefsKey), isNotEmpty);
  });
}
