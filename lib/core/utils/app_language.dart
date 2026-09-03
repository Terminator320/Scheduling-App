import 'dart:ui' show PlatformDispatcher;

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

/// Narrows any language code to the two locales the SERVER renders in.
String serverLocaleOf(String? code) => code == 'fr' ? 'fr' : 'en';

/// [serverLocaleOf] for the app's current language.
String get currentServerLocale =>
    serverLocaleOf(AppLanguageController.instance.value);

/// The language a FIRST launch should open in, read from the device.
String deviceServerLocale([Locale? locale]) {
  final code = (locale ?? PlatformDispatcher.instance.locale).languageCode;
  return serverLocaleOf(code.toLowerCase());
}
