import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final ThemeMode themeMode;
  final double textScale;
  final String language;

  const AppSettings({
    required this.themeMode,
    required this.textScale,
    required this.language,
  });
}

class SettingsService {
  static const _keyThemeMode = 'theme_mode';
  static const _keyTextScale = 'text_scale';
  static const _keyLanguage = 'language';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();

    final themeModeIndex = prefs.getInt(_keyThemeMode) ?? ThemeMode.system.index;
    final textScale = prefs.getDouble(_keyTextScale) ?? 1.0;
    final language = prefs.getString(_keyLanguage) ?? 'en';

    return AppSettings(
      themeMode: ThemeMode.values[themeModeIndex],
      textScale: textScale,
      language: language,
    );
  }

  Future<void> save({ThemeMode? themeMode, double? textScale, String? language}) async {
    final prefs = await SharedPreferences.getInstance();

    if (themeMode != null) await prefs.setInt(_keyThemeMode, themeMode.index);
    if (textScale != null) await prefs.setDouble(_keyTextScale, textScale);
    if (language != null) await prefs.setString(_keyLanguage, language);
  }
}
