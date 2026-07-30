import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/theme/themes.dart';

void main() {
  test('both themes register all four extensions', () {
    for (final theme in [lightTheme(), darkTheme()]) {
      expect(theme.extension<AppStatusColors>(), isNotNull);
      expect(theme.extension<AppCardStyle>(), isNotNull);
      expect(theme.extension<AppPalette>(), isNotNull);
      expect(theme.extension<AppMonoType>(), isNotNull);
    }
  });

  test('primary is the saturated fill blue, accent is the text blue', () {
    expect(lightTheme().colorScheme.primary, AppColors.blue);
    expect(lightTheme().palette.primaryAccent, AppColors.blue);
    expect(darkTheme().colorScheme.primary, AppColors.darkBlueFill);
    expect(darkTheme().palette.primaryAccent, AppColors.darkBlueText);
  });

  test('the notice surface is dark ink in both themes', () {
    expect(lightTheme().colorScheme.inverseSurface, AppColors.ink);
    expect(darkTheme().colorScheme.inverseSurface, AppColors.darkNotice);
  });

  test('M3 elevation tinting is disabled', () {
    expect(lightTheme().colorScheme.surfaceTint, Colors.transparent);
    expect(darkTheme().colorScheme.surfaceTint, Colors.transparent);
  });

  test('every text style uses the bundled sans family', () {
    final ramp = lightTheme().textTheme;
    for (final style in [
      ramp.displayLarge,
      ramp.headlineLarge,
      ramp.headlineMedium,
      ramp.headlineSmall,
      ramp.titleLarge,
      ramp.titleMedium,
      ramp.titleSmall,
      ramp.bodyLarge,
      ramp.bodyMedium,
      ramp.bodySmall,
      ramp.labelLarge,
      ramp.labelMedium,
      ramp.labelSmall,
    ]) {
      expect(style?.fontFamily, kFontSans);
    }
  });

  test('mono styles use the bundled mono family', () {
    final mono = lightTheme().monoType;
    expect(mono.data.fontFamily, kFontMono);
    expect(mono.numeralHero.fontFamily, kFontMono);
  });

  test('no text style falls below the 11px floor', () {
    final ramp = lightTheme().textTheme;
    for (final style in [ramp.labelSmall, ramp.labelMedium, ramp.bodySmall]) {
      expect(style!.fontSize, greaterThanOrEqualTo(11.0));
    }
  });
}
