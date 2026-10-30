// test/unit/demo_mode_test.dart — demo mode is opt-in via the launch URL only.

import 'package:flutter_test/flutter_test.dart';
import 'package:beaty/core/demo/demo_mode.dart';

void main() {
  group('DemoMode.isRequestedFor', () {
    test('query marker (canonical)', () {
      expect(
          DemoMode.isRequestedFor(Uri.parse('https://paaxmusic.app/?demo=1')),
          isTrue);
      expect(
          DemoMode.isRequestedFor(
              Uri.parse('https://paaxmusic.app/?demo=true')),
          isTrue);
      expect(
          DemoMode.isRequestedFor(Uri.parse('https://paaxmusic.app/?demo=0')),
          isFalse);
    });

    test('path and fragment forms', () {
      expect(DemoMode.isRequestedFor(Uri.parse('https://paaxmusic.app/demo')),
          isTrue);
      expect(DemoMode.isRequestedFor(Uri.parse('https://paaxmusic.app/demo/')),
          isTrue);
      expect(DemoMode.isRequestedFor(Uri.parse('https://paaxmusic.app/#/demo')),
          isTrue);
      expect(
          DemoMode.isRequestedFor(
              Uri.parse('https://paaxmusic.app/#/demo?x=1')),
          isTrue);
    });

    test('normal launches are NOT demo mode', () {
      expect(DemoMode.isRequestedFor(Uri.parse('https://paaxmusic.app/')),
          isFalse);
      expect(DemoMode.isRequestedFor(Uri.parse('https://paaxmusic.app/#/')),
          isFalse);
      expect(DemoMode.isRequestedFor(Uri.parse('https://paaxmusic.app/login')),
          isFalse);
      expect(
          DemoMode.isRequestedFor(Uri.parse('https://paaxmusic.app/?ref=demo')),
          isFalse);
      expect(
          DemoMode.isRequestedFor(Uri.parse('paax://auth/confirm')), isFalse);
    });

    test('never requested off the web (mobile builds keep AuthGate)', () {
      // In the test VM kIsWeb is false regardless of Uri.base.
      expect(DemoMode.isRequested, isFalse);
    });
  });
}
