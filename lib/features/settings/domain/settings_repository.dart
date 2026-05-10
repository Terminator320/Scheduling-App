import 'package:flutter/material.dart';

import 'package:scheduling/features/settings/domain/models/app_settings.dart';

/// Persistence contract for `AppSettings`. Implementations live under
/// `data/`. Pure Dart so it can be mocked in tests without
/// `SharedPreferences` initialisation.
abstract class SettingsRepository {
  Future<AppSettings> load();

  Future<void> save({ThemeMode? themeMode, double? textScale, String? language});
}
