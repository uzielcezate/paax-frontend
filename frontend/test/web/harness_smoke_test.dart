@TestOn('browser')
library;

// Minimal browser-platform smoke test used to prove the
// `flutter test --platform chrome` harness itself works on a machine before
// trusting the YouTube player frame test next to it.

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('browser test harness runs', () {
    expect(1 + 1, 2);
  });
}
