import 'package:flutter/material.dart';

/// Whether [mode] currently resolves to dark.
bool isDarkMode(ThemeMode mode, Brightness platformBrightness) =>
    switch (mode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => platformBrightness == Brightness.dark,
    };

/// The opposite of the current dark mode (per [isDarkMode]).
ThemeMode toggledThemeMode(ThemeMode current, Brightness platformBrightness) =>
    isDarkMode(current, platformBrightness) ? ThemeMode.light : ThemeMode.dark;

class ThemeNotifier extends InheritedWidget {
  const ThemeNotifier({
    required this.themeMode,
    required this.toggleTheme,
    required this.textScale,
    required this.setTextScale,
    required this.setLanguage,
    required super.child,
    super.key,
  });
  final ThemeMode themeMode;
  final VoidCallback toggleTheme;

  final double textScale;
  final ValueChanged<double> setTextScale;

  final ValueChanged<String> setLanguage;

  static ThemeNotifier of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ThemeNotifier>()!;
  }

  @override
  bool updateShouldNotify(ThemeNotifier oldWidget) {
    return themeMode != oldWidget.themeMode || textScale != oldWidget.textScale;
  }
}
