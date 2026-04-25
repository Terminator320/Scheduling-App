import 'package:flutter/material.dart';

class ThemeNotifier extends InheritedWidget {
  final ThemeMode themeMode;
  final VoidCallback toggleTheme;

  const ThemeNotifier({
    super.key,
    required this.themeMode,
    required this.toggleTheme,
    required super.child,
  });

  static ThemeNotifier of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ThemeNotifier>()!;
  }

  bool get isDark => themeMode == ThemeMode.dark;

  @override
  bool updateShouldNotify(ThemeNotifier oldWidget) {
    return themeMode != oldWidget.themeMode;
  }
}
