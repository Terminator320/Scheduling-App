import 'package:scheduling/l10n/l10n.dart';

/// A common plumbing job type offered as a one-tap "quick fill" at the top of
/// the add-appointment form. Picking one seeds the service title and a typical
/// duration, standardizing titles (which also keeps search/reporting
/// consistent) and turning a multi-field booking into a couple of taps.
///
/// Display-only convenience — never stored. The appointment still saves with
/// its normal `status: 'pending'` and whatever the admin edits afterwards.
enum JobTemplate {
  leakDiagnostic(30),
  drainCleaning(60),
  faucetOrValve(45),
  toiletRepair(45),
  emergencyCall(90),
  waterHeater(120);

  const JobTemplate(this.defaultDurationMinutes);

  /// Typical on-site duration, used to seed the end time when a start time is
  /// already chosen.
  final int defaultDurationMinutes;

  /// Minutes-past-midnight of the seeded end time for a job starting at
  /// [startMinutesOfDay], clamped inside the same day so a late start can't
  /// wrap past midnight.
  int endMinutesOfDay(int startMinutesOfDay) =>
      (startMinutesOfDay + defaultDurationMinutes).clamp(0, 24 * 60 - 1);
}

/// Localized display title for a [JobTemplate] — the label on its picker chip
/// and the text seeded into the service-title field. Mirrors `statusLabel`.
String jobTemplateLabel(AppLocalizations l10n, JobTemplate template) =>
    switch (template) {
      JobTemplate.leakDiagnostic => l10n.calendar_jobTemplateLeakDiagnostic,
      JobTemplate.drainCleaning => l10n.calendar_jobTemplateDrainCleaning,
      JobTemplate.faucetOrValve => l10n.calendar_jobTemplateFaucetOrValve,
      JobTemplate.toiletRepair => l10n.calendar_jobTemplateToiletRepair,
      JobTemplate.emergencyCall => l10n.calendar_jobTemplateEmergencyCall,
      JobTemplate.waterHeater => l10n.calendar_jobTemplateWaterHeater,
    };
