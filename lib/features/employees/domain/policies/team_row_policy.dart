import 'package:scheduling/features/employees/domain/models/job_title.dart';
import 'package:scheduling/l10n/l10n.dart';

/// The team roster row's second line: `"<jobTitle> · <n> jobs today"`.
///
/// Each half is dropped when it says nothing — a person with no title and no
/// jobs booked falls back to their email, which is what the row showed before
/// P4 and is still the only thing left to identify them by.
String teamRowSubtitle({
  required AppLocalizations l10n,
  required JobTitle jobTitle,
  required int jobsToday,
  required String email,
}) {
  final parts = <String>[
    if (jobTitle != JobTitle.unset) jobTitleLabel(l10n, jobTitle),
    if (jobsToday > 0) l10n.employees_jobsToday(jobsToday),
  ];
  if (parts.isEmpty) return email;
  return parts.join(' · ');
}
