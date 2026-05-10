import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_settings.freezed.dart';

/// User-tunable application settings persisted via the
/// `SettingsRepository`. Pure-Dart data class — `ThemeMode` comes from
/// Flutter Material but is a value type, not a Firebase service.
@freezed
abstract class AppSettings with _$AppSettings {
  const factory AppSettings({
    @Default(ThemeMode.system) ThemeMode themeMode,
    @Default(1.0) double textScale,
    @Default('en') String language,
  }) = _AppSettings;
}
