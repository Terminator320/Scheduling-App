import 'package:flutter/material.dart';
import 'package:scheduling/features/settings/domain/models/app_settings.dart';
import 'package:scheduling/features/settings/domain/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPrefsSettingsRepository implements SettingsRepository {
  static const _keyThemeMode = 'theme_mode';
  static const _keyTextScale = 'text_scale';
  static const _keyLanguage = 'language';

  static ThemeMode _themeModeFromIndex(int? index) {
    if (index == null || index < 0 || index >= ThemeMode.values.length) {
      return ThemeMode.system;
    }
    return ThemeMode.values[index];
  }

  static double _sanitizeTextScale(double? value) {
    if (value == null || !value.isFinite || value <= 0) return 1;
    return value;
  }

  static String _sanitizeLanguage(String? value) =>
      value == 'fr' ? 'fr' : 'en';

  @override
  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();

    return AppSettings(
      themeMode: _themeModeFromIndex(prefs.getInt(_keyThemeMode)),
      textScale: _sanitizeTextScale(prefs.getDouble(_keyTextScale)),
      language: _sanitizeLanguage(prefs.getString(_keyLanguage)),
    );
  }

  @override
  Future<void> save({
    ThemeMode? themeMode,
    double? textScale,
    String? language,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    if (themeMode != null) await prefs.setInt(_keyThemeMode, themeMode.index);
    if (textScale != null) await prefs.setDouble(_keyTextScale, textScale);
    if (language != null) await prefs.setString(_keyLanguage, language);
  }
}
