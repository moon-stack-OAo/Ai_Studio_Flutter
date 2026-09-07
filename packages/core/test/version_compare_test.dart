import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeVersion', () {
    test('strips v and build metadata', () {
      expect(normalizeVersion('v1.0.7'), '1.0.7');
      expect(normalizeVersion('1.0.0+1'), '1.0.0');
      expect(normalizeVersion('1.2.3-beta.1'), '1.2.3');
      expect(normalizeVersion('  V2.0.0  '), '2.0.0');
      expect(normalizeVersion(''), '');
      expect(normalizeVersion(null), '');
    });
  });

  group('compareVersions / isRemoteNewer', () {
    test('equal versions', () {
      expect(compareVersions('1.0.0', '1.0.0'), 0);
      expect(compareVersions('v1.0.0+1', '1.0.0'), 0);
      expect(isRemoteNewer('1.0.0', '1.0.0'), isFalse);
    });

    test('remote newer', () {
      expect(compareVersions('1.0.7', '1.0.0'), greaterThan(0));
      expect(isRemoteNewer('1.0.7', '1.0.0'), isTrue);
      expect(isRemoteNewer('2.0.0', '1.9.9'), isTrue);
      expect(isRemoteNewer('1.0.10', '1.0.9'), isTrue);
    });

    test('local newer or equal', () {
      expect(isRemoteNewer('1.0.0', '1.0.7'), isFalse);
      expect(isRemoteNewer('1.0.0', '1.0.0+99'), isFalse);
    });

    test('uneven part lengths', () {
      expect(compareVersions('1.0', '1.0.0'), 0);
      expect(compareVersions('1.0.1', '1.0'), greaterThan(0));
      expect(compareVersions('1.1', '1.0.9'), greaterThan(0));
    });
  });
}
