/// The automatic Wave-import cadence, stored on `wave/connection` and chosen in
/// Settings. `fromRaw` pins the accepted wire strings explicitly (rather than
/// trusting `.name`) so the cross-boundary contract — also validated in the
/// `waveSetImportSchedule` function and switched on in `isImportDue` — can't be
/// silently changed by an enum-constant rename. Any null/empty/unknown value
/// falls to [off], the fail-safe default (never accidentally enables imports).
enum WaveImportSchedule {
  off,
  weekly,
  monthly;

  static WaveImportSchedule fromRaw(String? raw) => switch (raw) {
    'weekly' => weekly,
    'monthly' => monthly,
    _ => off,
  };

  /// The stored/wire string. Safe as `.name` here because the enum names
  /// already equal the accepted wire values.
  String get raw => name;
}
