import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/theme/theme_notifier.dart';

void main() {
  group('isDarkMode', () {
    test('explicit modes ignore platform brightness', () {
      expect(isDarkMode(ThemeMode.dark, Brightness.light), isTrue);
      expect(isDarkMode(ThemeMode.dark, Brightness.dark), isTrue);
      expect(isDarkMode(ThemeMode.light, Brightness.dark), isFalse);
      expect(isDarkMode(ThemeMode.light, Brightness.light), isFalse);
    });

    test('system resolves against platform brightness', () {
      expect(isDarkMode(ThemeMode.system, Brightness.dark), isTrue);
      expect(isDarkMode(ThemeMode.system, Brightness.light), isFalse);
    });
  });

  group('toggledThemeMode', () {
    test(
      'a dark phone on the default system mode flips to light in one tap',
      () {
        // The reported bug: system + dark used to need two taps.
        expect(
          toggledThemeMode(ThemeMode.system, Brightness.dark),
          ThemeMode.light,
        );
      },
    );

    test('a light phone on the default system mode flips to dark', () {
      expect(
        toggledThemeMode(ThemeMode.system, Brightness.light),
        ThemeMode.dark,
      );
    });

    test('explicit modes flip to their opposite regardless of the OS', () {
      expect(
        toggledThemeMode(ThemeMode.dark, Brightness.dark),
        ThemeMode.light,
      );
      expect(
        toggledThemeMode(ThemeMode.light, Brightness.light),
        ThemeMode.dark,
      );
    });
  });
}
