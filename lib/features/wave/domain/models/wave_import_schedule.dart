/// Wave auto-import cadence; unknown values default to off.
enum WaveImportSchedule {
  off,
  weekly,
  monthly;

  static WaveImportSchedule fromRaw(String? raw) => switch (raw) {
    'weekly' => weekly,
    'monthly' => monthly,
    _ => off,
  };

  /// Stored wire string.
  String get raw => name;
}
