import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/features/settings/data/shared_prefs_settings_repository.dart';
import 'package:scheduling/features/settings/domain/settings_repository.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SharedPrefsSettingsRepository(),
);

class SettingsSaveDebouncer {
  SettingsSaveDebouncer({this.delay = const Duration(milliseconds: 250)});

  final Duration delay;
  Timer? _timer;

  void run(Future<void> Function() save) {
    _timer?.cancel();
    _timer = Timer(delay, save);
  }

  void dispose() {
    _timer?.cancel();
  }
}
