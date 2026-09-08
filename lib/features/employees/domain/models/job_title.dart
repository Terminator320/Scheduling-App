import 'package:scheduling/l10n/l10n.dart';

/// What this person does on site. Stored as [raw]; an empty string means the
/// admin never picked one, which is a normal state and not an error.
///
/// Deliberately NOT the same axis as `role`, which stays the access flag
/// (`admin` / `employee`) and gates what the app lets them see.
enum JobTitle {
  unset(''),
  leadTech('lead_tech'),
  technician('technician'),
  apprentice('apprentice'),
  dispatcher('dispatcher');

  const JobTitle(this.raw);

  final String raw;

  /// Unknown and legacy values fall back to [unset] — mirrors
  /// `ClientType.fromRaw`.
  static JobTitle fromRaw(String? value) {
    final trimmed = (value ?? '').trim();
    for (final title in JobTitle.values) {
      if (title.raw == trimmed) return title;
    }
    return JobTitle.unset;
  }

  /// Whether someone with this title is crew — the people a job can be
  /// assigned to.
  ///
  /// A dispatcher schedules the work rather than doing it, so they are hidden
  /// from the assignee picker and from the dashboard's per-person job numbers
  /// (workload rows, daily capacity, availability conflicts), where they would
  /// otherwise sit at a permanent zero and inflate capacity. It is NOT an
  /// access flag — that stays `role` — and it never touches assignees that are
  /// already stored on a job.
  bool get isAssignable => this != JobTitle.dispatcher;

  /// The four pickable titles, in the order the chips render.
  static const List<JobTitle> pickable = [
    JobTitle.leadTech,
    JobTitle.technician,
    JobTitle.apprentice,
    JobTitle.dispatcher,
  ];
}

/// Localized chip label (mirrors `clientTypeLabel`).
String jobTitleLabel(AppLocalizations l10n, JobTitle title) => switch (title) {
  JobTitle.unset => '',
  JobTitle.leadTech => l10n.employees_jobTitleLeadTech,
  JobTitle.technician => l10n.employees_jobTitleTechnician,
  JobTitle.apprentice => l10n.employees_jobTitleApprentice,
  JobTitle.dispatcher => l10n.employees_jobTitleDispatcher,
};
