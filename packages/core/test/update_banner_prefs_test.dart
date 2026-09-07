import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UpdateBannerPrefs', () {
    late SharedPreferences prefs;
    late UpdateBannerPrefs bannerPrefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      bannerPrefs = UpdateBannerPrefs(prefs: prefs);
    });

    test('shouldShowFor true when never dismissed', () async {
      expect(await bannerPrefs.shouldShowFor('1.2.0'), isTrue);
    });

    test('dismiss same version hides; higher version shows again', () async {
      await bannerPrefs.dismissVersion('1.2.0');
      expect(await bannerPrefs.loadDismissedVersion(), '1.2.0');
      expect(await bannerPrefs.shouldShowFor('1.2.0'), isFalse);
      expect(await bannerPrefs.shouldShowFor('v1.2.0+3'), isFalse);
      expect(await bannerPrefs.shouldShowFor('1.2.1'), isTrue);
      expect(await bannerPrefs.shouldShowFor('1.3.0'), isTrue);
    });

    test('clear restores prompts', () async {
      await bannerPrefs.dismissVersion('2.0.0');
      await bannerPrefs.clear();
      expect(await bannerPrefs.loadDismissedVersion(), isNull);
      expect(await bannerPrefs.shouldShowFor('2.0.0'), isTrue);
    });

    test('empty available never shows', () async {
      expect(await bannerPrefs.shouldShowFor(''), isFalse);
      expect(await bannerPrefs.shouldShowFor(null), isFalse);
    });
  });
}
