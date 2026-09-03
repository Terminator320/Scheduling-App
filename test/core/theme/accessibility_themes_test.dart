import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/theme/themes.dart';

/// `docs/legal/accessibility.html` publicly claims the app picks up iOS **Bold
/// Text** and **Increase Contrast** "straight away".
void main() {
  group('boldTextTheme', () {
    test('moves every text style one weight step up', () {
      final base = lightTheme();
      final bold = boldTextTheme(base);

      // A representative spread: body, title and label are the three families
      // the app actually renders.
      for (final pair in [
        (base.textTheme.bodyMedium, bold.textTheme.bodyMedium),
        (base.textTheme.titleLarge, bold.textTheme.titleLarge),
        (base.textTheme.labelSmall, bold.textTheme.labelSmall),
      ]) {
        final before = pair.$1!.fontWeight ?? FontWeight.w400;
        final after = pair.$2!.fontWeight!;
        expect(
          FontWeight.values.indexOf(after),
          FontWeight.values.indexOf(before) + 1,
        );
      }
    });

    test('keeps the scale RELATIVE, rather than flattening it to bold', () {
      // Jumping every style straight to w700 destroys the weight contrast the
      // type scale uses to separate a title from its body.
      final bold = boldTextTheme(lightTheme());
      final body = bold.textTheme.bodyMedium!.fontWeight!;
      final label = bold.textTheme.labelSmall!.fontWeight!;

      expect(
        FontWeight.values.indexOf(label),
        greaterThan(FontWeight.values.indexOf(body)),
      );
    });

    test('a w900 style has nowhere to go and is left alone', () {
      final base = ThemeData(
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontWeight: FontWeight.w900),
        ),
      );

      expect(
        boldTextTheme(base).textTheme.bodyMedium!.fontWeight,
        FontWeight.w900,
      );
    });

    test('changes nothing but weight', () {
      final base = lightTheme();
      final bold = boldTextTheme(base);

      expect(
        bold.textTheme.bodyMedium!.fontSize,
        base.textTheme.bodyMedium!.fontSize,
      );
      expect(
        bold.textTheme.bodyMedium!.color,
        base.textTheme.bodyMedium!.color,
      );
      expect(bold.colorScheme, base.colorScheme);
    });
  });

  group('the high-contrast pair', () {
    test('lifts secondary text off the muted token, in both themes', () {
      // The whole point of the setting: `onSurfaceVariant` is what captions,
      // hints and secondary rows read.
      expect(
        highContrastLightTheme().colorScheme.onSurfaceVariant,
        isNot(lightTheme().colorScheme.onSurfaceVariant),
      );
      expect(
        highContrastDarkTheme().colorScheme.onSurfaceVariant,
        isNot(darkTheme().colorScheme.onSurfaceVariant),
      );
    });

    test('lifts the hairlines too', () {
      expect(
        highContrastLightTheme().colorScheme.outline,
        isNot(lightTheme().colorScheme.outline),
      );
      expect(
        highContrastDarkTheme().colorScheme.outline,
        isNot(darkTheme().colorScheme.outline),
      );
    });

    test('repaints the TEXT STYLES, not just the scheme', () {
      // `bodySmall` and `labelMedium` hard-code a muted colour in the type
      // scale, so a ColorScheme swap alone leaves the very text this setting
      // exists for unchanged.
      final hc = highContrastLightTheme();
      expect(
        hc.textTheme.bodySmall!.color,
        hc.colorScheme.onSurfaceVariant,
      );
      expect(
        hc.textTheme.labelMedium!.color,
        hc.colorScheme.onSurfaceVariant,
      );
    });

    test('leaves the brand colours alone', () {
      // Lifting these would make it a different app rather than a more legible
      // one.
      expect(
        highContrastLightTheme().colorScheme.primary,
        lightTheme().colorScheme.primary,
      );
      expect(
        highContrastDarkTheme().colorScheme.primary,
        darkTheme().colorScheme.primary,
      );
    });

    test('keeps each theme its own brightness', () {
      expect(highContrastLightTheme().brightness, Brightness.light);
      expect(highContrastDarkTheme().brightness, Brightness.dark);
    });

    test('carries the four ThemeExtensions through', () {
      // Every `theme.palette` / `theme.statusColors` call site resolves through
      // these; a copyWith that dropped them would throw at the first read.
      final hc = highContrastLightTheme();
      expect(hc.extensions.length, lightTheme().extensions.length);
    });
  });
}
