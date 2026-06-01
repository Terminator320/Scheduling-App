import 'package:flutter/material.dart';

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

  bool get isDark => themeMode == ThemeMode.dark;

  @override
  bool updateShouldNotify(ThemeNotifier oldWidget) {
    return themeMode != oldWidget.themeMode || textScale != oldWidget.textScale;
  }
}
