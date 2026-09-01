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

/// The language a FIRST launch should open in, read from the device.
///
/// `serverLocaleOf(null)` answers `'en'`, and nothing used to consult the
/// platform at all — so a francophone plumber whose iPhone is in French
/// installed the app and got English. It compounds well past the UI:
/// `currentServerLocale` is what registers the FCM token locale, the widget
/// payload and the Live Activity locale, so their pushes, Lock Screen cards
/// and home-screen widget were English too, until they found the Settings
/// toggle. For a Quebec business that is close to a first-run defect.
///
/// Only ever a SEED. Once a language is stored, the stored value wins — the
/// preference is the person's, not the handset's, and re-deriving it from the
/// device would silently undo an explicit choice on every launch.
String deviceServerLocale([Locale? locale]) {
  final code = (locale ?? PlatformDispatcher.instance.locale).languageCode;
  return serverLocaleOf(code.toLowerCase());
}
