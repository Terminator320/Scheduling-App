import 'package:scheduling/l10n/l10n.dart';

/// Display-only quick-fill templates for the add form.
enum JobTemplate {
  leakDiagnostic(30),
  drainCleaning(60),
  faucetOrValve(45),
  toiletRepair(45),
  emergencyCall(90),
  waterHeater(120);

  const JobTemplate(this.defaultDurationMinutes);

  /// Typical on-site duration.
  final int defaultDurationMinutes;

  /// Seeded end time, clamped to the same day.
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
