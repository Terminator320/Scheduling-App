/// How long a settings change waits before it is written to SharedPreferences.
///
/// Named and kept beside the settings feature because it is its own cost dial,
/// distinct from the shared search debounce.
const Duration kSettingsSaveDebounce = Duration(milliseconds: 250);
