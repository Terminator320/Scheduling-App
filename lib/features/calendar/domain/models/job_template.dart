import 'package:scheduling/l10n/l10n.dart';

/// Quick-fill job templates for the add form. These are just a display-only convenience and are never stored.
enum JobTemplate {
  leakDiagnostic(30),
  drainCleaning(60),
  faucetOrValve(45),
  toiletRepair(45),
  emergencyCall(90),
  waterHeater(120);

  const JobTemplate(this.defaultDurationMinutes);

  /// Typical time this job takes on-site. Used to seed the end time once a start time is set.
  final int defaultDurationMinutes;

  /// The seeded end time as minutes-past-midnight, clamped so it stays on the same day.
  int endMinutesOfDay(int startMinutesOfDay) =>
      (startMinutesOfDay + defaultDurationMinutes).clamp(0, 24 * 60 - 1);
}

/// Localized display title for a [JobTemplate] (mirrors `statusLabel`).
String jobTemplateLabel(AppLocalizations l10n, JobTemplate template) =>
    switch (template) {
      JobTemplate.leakDiagnostic => l10n.calendar_jobTemplateLeakDiagnostic,
      JobTemplate.drainCleaning => l10n.calendar_jobTemplateDrainCleaning,
      JobTemplate.faucetOrValve => l10n.calendar_jobTemplateFaucetOrValve,
      JobTemplate.toiletRepair => l10n.calendar_jobTemplateToiletRepair,
      JobTemplate.emergencyCall => l10n.calendar_jobTemplateEmergencyCall,
      JobTemplate.waterHeater => l10n.calendar_jobTemplateWaterHeater,
    };
