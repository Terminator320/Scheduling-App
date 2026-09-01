import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/utils/app_language.dart';
import 'package:scheduling/features/settings/data/shared_prefs_settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // Pinned English so the pre-existing defaults below stay deterministic
  // wherever the suite runs; the seed itself has its own group at the bottom.
  SharedPrefsSettingsRepository repo() =>
      SharedPrefsSettingsRepository(deviceLanguage: () => 'en');

  group('load', () {
    test('returns defaults when nothing saved (device language seeds it)',
        () async {
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

    test('falls back to defaults when persisted values are invalid', () async {
      SharedPreferences.setMockInitialValues({
        'theme_mode': 99,
        'text_scale': -1.0,
        'language': 'es',
      });

      final settings = await repo().load();

      expect(settings.themeMode, ThemeMode.system);
      expect(settings.textScale, 1.0);
      expect(settings.language, 'en');
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
        language: 'fr',
      );

      final settings = await repo().load();
      expect(settings.themeMode, ThemeMode.dark);
      expect(settings.textScale, 2.0);
      expect(settings.language, 'fr');
    });

    test('an unsupported language loads back as English', () async {
      // The app ships EN + FR only, so a stored locale from anywhere else -
      // an older build, a hand-edited pref - must not reach MaterialApp.
      await repo().save(language: 'es');

      expect((await repo().load()).language, 'en');
    });
  });

  group('the first-launch language seed', () {
    // `serverLocaleOf(null)` answered 'en' and nothing consulted the platform,
    // so a francophone plumber whose iPhone is in French installed the app and
    // got English — along with English pushes, Lock Screen cards and widget,
    // because currentServerLocale is what registers all three.
    test('a French device opens in French', () async {
      final settings = await SharedPrefsSettingsRepository(
        deviceLanguage: () => 'fr',
      ).load();

      expect(settings.language, 'fr');
    });

    test('an unsupported device language still lands on English', () async {
      final settings = await SharedPrefsSettingsRepository(
        deviceLanguage: () => serverLocaleOf('es'),
      ).load();

      expect(settings.language, 'en');
    });

    test('a STORED preference beats the device, in both directions', () async {
      // The seed must never re-derive on later launches: that would silently
      // undo an explicit choice every time the app opened.
      final french = SharedPrefsSettingsRepository(deviceLanguage: () => 'fr');
      await french.save(language: 'en');
      expect((await french.load()).language, 'en');

      SharedPreferences.setMockInitialValues({});
      final english = SharedPrefsSettingsRepository(deviceLanguage: () => 'en');
      await english.save(language: 'fr');
      expect((await english.load()).language, 'fr');
    });
  });

  group('deviceServerLocale', () {
    test('narrows any French variant to fr', () {
      expect(deviceServerLocale(const Locale('fr', 'CA')), 'fr');
      expect(deviceServerLocale(const Locale('fr')), 'fr');
    });

    test('anything the app does not ship reads as en', () {
      expect(deviceServerLocale(const Locale('es', 'MX')), 'en');
      expect(deviceServerLocale(const Locale('en', 'GB')), 'en');
    });

    test('is case-insensitive on the language subtag', () {
      // A platform locale can arrive with an uppercase subtag; without the
      // fold this would silently fall through to English.
      expect(deviceServerLocale(const Locale('FR', 'CA')), 'fr');
    });
  });
}
