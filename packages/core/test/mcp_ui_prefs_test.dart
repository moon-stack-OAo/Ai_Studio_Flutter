import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('dismiss unconfigured hint persists', () async {
    final prefs = McpUiPrefs();
    await prefs.ensureLoaded();
    expect(prefs.dismissUnconfiguredHint, isFalse);

    await prefs.dismissUnconfiguredHintBanner();
    expect(prefs.dismissUnconfiguredHint, isTrue);

    final again = McpUiPrefs();
    await again.ensureLoaded();
    expect(again.dismissUnconfiguredHint, isTrue);
  });

  test('clear restores hint eligibility', () async {
    final prefs = McpUiPrefs();
    await prefs.dismissUnconfiguredHintBanner();
    await prefs.clearDismissUnconfiguredHint();
    expect(prefs.dismissUnconfiguredHint, isFalse);
  });
}
