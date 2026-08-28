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
///
/// The one owner of that decision. It was re-spelled at six sites — three off
/// `AppLanguageController.instance.value`, two off `Localizations.localeOf`
/// and one sanitizing the stored preference — each deciding which language a
/// push, widget payload, Live Activity or reverse-geocode comes back in. Two
/// sources answering the same question independently is how a device
/// registers one locale and renders another.
String serverLocaleOf(String? code) => code == 'fr' ? 'fr' : 'en';

/// [serverLocaleOf] for the app's current language.
String get currentServerLocale =>
    serverLocaleOf(AppLanguageController.instance.value);
