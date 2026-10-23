// test/unit/orientation_policy_test.dart — Visual polish §7.
//
// Phones lock to portrait; tablets do not. The decision uses the shortest
// side, so it is identical in both orientations of the same device.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:beaty/core/utils/orientation_policy.dart';

void main() {
  test('phones lock to portrait in either orientation', () {
    expect(shouldLockPortrait(const Size(360, 800)), isTrue);
    expect(shouldLockPortrait(const Size(800, 360)), isTrue); // rotated
    expect(shouldLockPortrait(const Size(430, 932)), isTrue);
    expect(shouldLockPortrait(const Size(320, 568)), isTrue);
  });

  test('tablets and large screens are not locked', () {
    expect(shouldLockPortrait(const Size(600, 960)), isFalse); // boundary
    expect(shouldLockPortrait(const Size(960, 600)), isFalse);
    expect(shouldLockPortrait(const Size(800, 1280)), isFalse);
    expect(shouldLockPortrait(const Size(1280, 800)), isFalse);
  });

  test('a device never changes class after rotation', () {
    for (final s in [const Size(412, 915), const Size(834, 1194)]) {
      expect(shouldLockPortrait(s), shouldLockPortrait(Size(s.height, s.width)));
    }
  });

  test('logical size is derived from physical size and pixel ratio', () {
    // 1080×2400 @ 3.0 → 360×800 logical.
    expect(const Size(1080, 2400) / 3.0, const Size(360, 800));
  });
}
