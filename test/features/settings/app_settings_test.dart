import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/settings/domain/models/app_settings.dart';

void main() {
  group('AppSettings', () {
    test('value equality works (freezed)', () {
      const a = AppSettings(textScale: 1.25, language: 'fr');
      const b = AppSettings(textScale: 1.25, language: 'fr');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('default values', () {
      const s = AppSettings();
      expect(s.themeMode, ThemeMode.system);
      expect(s.textScale, 1.0);
      expect(s.language, 'en');
    });

    test('copyWith preserves untouched fields', () {
      const original = AppSettings(textScale: 1.25, language: 'fr');
      final updated = original.copyWith(themeMode: ThemeMode.dark);
      expect(updated.themeMode, ThemeMode.dark);
      expect(updated.textScale, 1.25);
      expect(updated.language, 'fr');
    });
  });
}
