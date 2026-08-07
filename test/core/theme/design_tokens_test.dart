import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/theme/design_tokens.dart';

void main() {
  test('crew palette has ten distinct colours', () {
    expect(AppColors.crewPalette, hasLength(10));
    expect(
      AppColors.crewPalette.map((c) => c.toARGB32()).toSet(),
      hasLength(10),
    );
  });

  test('every canonical crew colour has a dark counterpart', () {
    const dark = AppPalette.dark;
    for (final colour in AppColors.crewPalette) {
      expect(
        dark.crewOverride[colour.toARGB32()],
        isNotNull,
        reason: '${colour.toARGB32().toRadixString(16)} has no dark lift',
      );
    }
  });

  test('crewColorOf is identity in light and lifts in dark', () {
    final light = ThemeData(extensions: const [AppPalette.light]);
    final dark = ThemeData(extensions: const [AppPalette.dark]);
    const blue = 0xFF005CC8;
    expect(crewColorOf(light, blue), const Color(blue));
    expect(crewColorOf(dark, blue), const Color(0xFF4B90F7));
  });

  test('crewColorOf HSL-lifts a custom colour only in dark', () {
    final light = ThemeData(extensions: const [AppPalette.light]);
    final dark = ThemeData(extensions: const [AppPalette.dark]);
    const custom = 0xFF123456; // not in the canonical palette
    expect(crewColorOf(light, custom), const Color(custom));
    final lifted = crewColorOf(dark, custom);
    expect(
      HSLColor.fromColor(lifted).lightness,
      greaterThan(HSLColor.fromColor(const Color(custom)).lightness),
    );
  });

  test('avatarForegroundFor returns contrast in light, hue-ink in dark', () {
    final light = ThemeData(extensions: const [AppPalette.light]);
    final dark = ThemeData(extensions: const [AppPalette.dark]);
    const mint = Color(0xFF2BC48E);
    expect(avatarForegroundFor(light, mint), Colors.black);
    final inked = avatarForegroundFor(dark, mint);
    expect(HSLColor.fromColor(inked).lightness, lessThan(0.15));
    expect(inked, isNot(Colors.black)); // keeps the hue, not pure black
  });
}
