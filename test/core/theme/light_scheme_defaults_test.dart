// The light ColorScheme leaves onPrimary, onError and surface to
// ColorScheme.light's defaults, because they already equal the tokens we want
// and spelling them out trips avoid_redundant_argument_values. That is only
// safe while the defaults keep matching — these tests are what pins them, so a
// Flutter upgrade that changes a default fails here instead of silently
// repainting every screen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/theme/themes.dart';

void main() {
  group('light scheme inherited defaults still match the tokens', () {
    late ColorScheme scheme;

    setUp(() => scheme = lightTheme().colorScheme);

    test('surface is the white paper token', () {
      expect(scheme.surface, AppColors.surface);
    });

    test('onPrimary contrasts the fill blue', () {
      expect(scheme.onPrimary, Colors.white);
      expect(
        contrastingForegroundFor(scheme.primary),
        Colors.white,
        reason: 'the default only works while primary stays a dark fill',
      );
    });

    test('onError contrasts the error red', () {
      expect(scheme.onError, Colors.white);
      expect(contrastingForegroundFor(scheme.error), Colors.white);
    });
  });
}
