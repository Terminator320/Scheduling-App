import 'package:flutter/material.dart';

import 'package:scheduling/features/settings/domain/models/app_settings.dart';

abstract class SettingsRepository {
  Future<AppSettings> load();

  Future<void> save({ThemeMode? themeMode, double? textScale, String? language});
}
