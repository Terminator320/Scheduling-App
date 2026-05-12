import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AppLanguageController extends ValueNotifier<String> {
  AppLanguageController._() : super('en') {
    Intl.defaultLocale = 'en_CA';
  }

  static final AppLanguageController instance = AppLanguageController._();

  void setLanguage(String code) {
    if (code == value) return;
    Intl.defaultLocale = code == 'fr' ? 'fr_CA' : 'en_CA';
    value = code;
  }
}

class AppLanguageScope extends InheritedNotifier<AppLanguageController> {
  const AppLanguageScope({
    required AppLanguageController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static AppLanguageController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppLanguageScope>();
    return scope?.notifier ?? AppLanguageController.instance;
  }
}
