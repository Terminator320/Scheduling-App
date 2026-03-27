import 'package:flutter/material.dart';

class AppThemeModeController extends ValueNotifier<bool> {
  AppThemeModeController._() : super(false);

  static final AppThemeModeController instance = AppThemeModeController._();

  bool get isDark => value;

  void setDark(bool isDark) {
    if (value == isDark) return;
    value = isDark;
  }

  void toggle() => setDark(!value);
}

class AppThemeModeScope extends InheritedNotifier<AppThemeModeController> {
  const AppThemeModeScope({
    super.key,
    required AppThemeModeController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppThemeModeController of(BuildContext context) {
    final scope =
    context.dependOnInheritedWidgetOfExactType<AppThemeModeScope>();
    return scope?.notifier ?? AppThemeModeController.instance;
  }
}

String themePathSuffix(BuildContext context) {
  return AppThemeModeScope.of(context).isDark ? 'dark' : 'light';
}
