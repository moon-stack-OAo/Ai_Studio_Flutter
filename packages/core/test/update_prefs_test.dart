import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UpdatePrefs', () {
    late SharedPreferences prefs;
    late UpdatePrefs updatePrefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      updatePrefs = UpdatePrefs(prefs: prefs);
    });

    test('defaults: autoCheck true, no skip/available', () async {
      await updatePrefs.load();
      expect(updatePrefs.autoCheckUpdate, isTrue);
      expect(updatePrefs.skippedUpdateVersion, isNull);
      expect(updatePrefs.availableUpdateVersion, isNull);
      expect(updatePrefs.hasAvailableUpdate, isFalse);
    });

    test('setAutoCheckUpdate persists', () async {
      await updatePrefs.setAutoCheckUpdate(false);
      expect(updatePrefs.autoCheckUpdate, isFalse);
      expect(prefs.getBool(UpdatePrefs.autoCheckKey), isFalse);

      final again = UpdatePrefs(prefs: prefs);
      await again.load();
      expect(again.autoCheckUpdate, isFalse);
    });

    test('skip suppresses prompt and badge; higher version prompts', () async {
      await updatePrefs.setAvailableUpdate('1.2.0');
      expect(updatePrefs.hasAvailableUpdate, isTrue);

      await updatePrefs.skipUpdateVersion('1.2.0');
      expect(updatePrefs.skippedUpdateVersion, '1.2.0');
      expect(updatePrefs.availableUpdateVersion, isNull);
      expect(updatePrefs.hasAvailableUpdate, isFalse);
      expect(await updatePrefs.shouldPromptFor('1.2.0'), isFalse);
      expect(await updatePrefs.shouldPromptFor('v1.2.0+9'), isFalse);
      expect(await updatePrefs.shouldPromptFor('1.2.1'), isTrue);
    });

    test('manual clearSkipped restores prompt', () async {
      await updatePrefs.skipUpdateVersion('2.0.0');
      await updatePrefs.clearSkippedUpdateVersion();
      expect(await updatePrefs.shouldPromptFor('2.0.0'), isTrue);
    });

    test('available != skipped drives hasAvailableUpdate', () async {
      await updatePrefs.skipUpdateVersion('1.0.0');
      await updatePrefs.setAvailableUpdate('1.1.0');
      expect(updatePrefs.hasAvailableUpdate, isTrue);

      await updatePrefs.setAvailableUpdate('1.0.0');
      expect(updatePrefs.hasAvailableUpdate, isFalse);
    });

    test('migrates legacy dismissed_version key once', () async {
      await prefs.setString(
        UpdatePrefs.legacyDismissedVersionKey,
        'v3.1.0+2',
      );
      await updatePrefs.load();
      expect(updatePrefs.skippedUpdateVersion, '3.1.0');
      expect(prefs.getString(UpdatePrefs.skippedVersionKey), '3.1.0');
      expect(prefs.getString(UpdatePrefs.legacyDismissedVersionKey), isNull);
    });
  });

  group('friendly update errors', () {
    test('maps semaphore / timeout wording', () {
      expect(
        friendlyUpdateNetworkError(Exception('信号灯超时时间已到')),
        contains('请求超时'),
      );
      expect(
        friendlyUpdateInstallError(Exception('TimeoutException after 0:00:30')),
        contains('网络不稳定'),
      );
    });

    test('signature errors are not retryable', () {
      expect(
        isRetryableUpdateInstallError(const UpdateException('签名校验失败')),
        isFalse,
      );
      expect(
        isRetryableUpdateInstallError(Exception('connection reset')),
        isTrue,
      );
    });
  });
}
