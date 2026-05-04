import 'package:flutter/material.dart';

class AppLanguageController extends ValueNotifier<String> {
  AppLanguageController._() : super('en');

  static final AppLanguageController instance = AppLanguageController._();

  bool get isFrench => value == 'fr';

  void setLanguage(String code) {
    if (code == value) return;
    value = code;
  }
}

class AppLanguageScope extends InheritedNotifier<AppLanguageController> {
  const AppLanguageScope({
    super.key,
    required AppLanguageController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppLanguageController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppLanguageScope>();
    return scope?.notifier ?? AppLanguageController.instance;
  }
}
