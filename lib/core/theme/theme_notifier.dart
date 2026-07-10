import 'package:flutter/material.dart';

/// Whether [mode] renders dark *right now*, resolving [ThemeMode.system]
/// against the live OS [platformBrightness].
///
/// The default mode is `system`, so `mode == ThemeMode.dark` alone reports
/// "light" on a dark phone — which parks the toggle switch in the wrong
/// position and makes its first tap a no-op (it sets an explicit dark that
/// looks identical). Resolving `system` here is what lets a single tap flip
/// what's actually on screen.
bool isDarkMode(ThemeMode mode, Brightness platformBrightness) =>
    switch (mode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => platformBrightness == Brightness.dark,
    };

/// The mode a light/dark toggle should move to from [current] — always the
/// opposite of what's displayed now (per [isDarkMode]), so one tap changes the
/// appearance even from the default `system` mode.
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
