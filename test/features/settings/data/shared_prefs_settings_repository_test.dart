import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/settings/data/shared_prefs_settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  SharedPrefsSettingsRepository repo() => SharedPrefsSettingsRepository();

  group('load', () {
    test('returns defaults when nothing saved', () async {
      final settings = await repo().load();

      expect(settings.themeMode, ThemeMode.system);
      expect(settings.textScale, 1.0);
      expect(settings.language, 'en');
    });

    test('returns persisted themeMode after save', () async {
      await repo().save(themeMode: ThemeMode.dark);

      final settings = await repo().load();
      expect(settings.themeMode, ThemeMode.dark);
    });

    test('returns persisted textScale after save', () async {
      await repo().save(textScale: 1.5);

      final settings = await repo().load();
      expect(settings.textScale, 1.5);
    });

    test('returns persisted language after save', () async {
      await repo().save(language: 'fr');

      final settings = await repo().load();
      expect(settings.language, 'fr');
    });
  });

  group('save', () {
    test('null fields do not overwrite existing values', () async {
      await repo().save(themeMode: ThemeMode.light, textScale: 1.2);
      // Saving only language should not reset themeMode or textScale.
      await repo().save(language: 'fr');

      final settings = await repo().load();
      expect(settings.themeMode, ThemeMode.light);
      expect(settings.textScale, 1.2);
      expect(settings.language, 'fr');
    });

    test('saves all fields independently', () async {
      await repo().save(
        themeMode: ThemeMode.dark,
        textScale: 2,
        language: 'es',
      );

      final settings = await repo().load();
      expect(settings.themeMode, ThemeMode.dark);
      expect(settings.textScale, 2.0);
      expect(settings.language, 'es');
    });
  });
}
