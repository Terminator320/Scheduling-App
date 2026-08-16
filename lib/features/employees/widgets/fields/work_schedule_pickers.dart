import 'package:flutter/material.dart';

import 'package:scheduling/core/adaptive/adaptive_action_sheet.dart';
import 'package:scheduling/features/calendar/domain/month_grid.dart';
import 'package:scheduling/features/employees/domain/policies/work_schedule_policy.dart';
import 'package:scheduling/l10n/l10n.dart';

/// The widget-layer half of the work-schedule rules: the pieces that need a
/// `BuildContext` — one pushes a route, the other reads `Localizations`.
///
/// They lived in `domain/policies/work_schedule_policy.dart`, which made it
/// the only domain file in the repo that shows UI, and forced an unqualified
/// `package:flutter/material.dart` plus `l10n` into the domain layer (every
/// other material import there is a `show TimeOfDay` / `show Color`). It sits
/// beside `availability_panel.dart`, the shared surface both callers of these
/// render. The pure part — `kMaxJobsOptions` and `maxJobsLabel` — STAYS
/// in the policy, since that is the value rule the single-owner rule exists
/// for.

/// Names a set of STORED (Sunday-indexed) day numbers as prose: "Sun, Wed".
///
/// It resolves the labels itself precisely so the unrotated rule has one owner:
/// `weekdayAbbreviationsForLocale` is Sunday-indexed like [days], and handing a
/// display-ordered list to a caller that indexes by stored number silently
/// names the wrong day. Used by both surfaces that report availability
/// conflicts — the dashboard's Attention list and My details.
String joinWeekdayNames(BuildContext context, Set<int> days) {
  final labels = weekdayAbbreviationsForLocale(
    Localizations.localeOf(context).toString(),
  );
  final sorted = days.toList()..sort();
  return [for (final day in sorted) labels[day]].join(', ');
}

/// The one daily-cap picker, shared by the admin Team sheet and My details.
///
/// Both offer the same field, so the option list and the label rule have one
/// owner — a hand-mirrored copy let a change to either land on one screen only.
/// Resolves to null when the sheet was dismissed.
Future<int?> showMaxJobsPicker(BuildContext context) {
  final l10n = context.l10n;
  return showAdaptiveActionSheet<int>(
    context,
    title: l10n.employees_maxJobsPerDay,
    actions: [
      for (final option in kMaxJobsOptions)
        AdaptiveSheetAction(label: maxJobsLabel(l10n, option), value: option),
    ],
  );
}
