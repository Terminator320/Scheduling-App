import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/calendar/domain/month_grid.dart';
import 'package:scheduling/features/employees/widgets/fields/availability_panel.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/warning_note.dart';
import 'package:scheduling/shared/widgets/primitives/mono_section_label.dart';

export 'package:scheduling/features/employees/widgets/fields/availability_panel.dart'
    show AvailabilityChanged;

/// Day toggles, hours and on-call — **applied immediately** (P5 spec).
///
/// Deliberately unlike the identity section above it, which is explicitly
/// saved. These are switches: one that needs a second confirmation reads as
/// broken, and the write is a single allowlisted patch that cannot half-apply.
///
/// The panel itself is [AvailabilityPanel], shared with the admin's Team sheet
/// so the two screens cannot drift on how a row looks or which time picker it
/// opens. This widget owns only what is specific to the self-service screen:
/// the heading, the blurb, and the booked-work warning.
///
/// Nothing is ever auto-unassigned. Turning off a day that still holds work
/// shows the amber note and leaves the jobs where they are for a human to move.
class MyAvailabilitySection extends StatelessWidget {
  const MyAvailabilitySection({
    required this.workingDays,
    required this.workStartMinutes,
    required this.workEndMinutes,
    required this.onCall,
    required this.conflictDays,
    required this.onChanged,
    super.key,
  });

  final List<bool> workingDays;
  final int workStartMinutes;
  final int workEndMinutes;
  final bool onCall;

  /// Sunday-indexed weekdays being switched off that still hold booked work.
  final Set<int> conflictDays;
  final AvailabilityChanged onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MonoSectionLabel(l10n.settings_myAvailability),
        const SizedBox(height: AppSpacing.sp8),
        Text(
          l10n.settings_myAvailabilityBlurb,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sp16),
        AvailabilityPanel(
          workingDays: workingDays,
          workStartMinutes: workStartMinutes,
          workEndMinutes: workEndMinutes,
          onCall: onCall,
          onCallKey: const Key('myOnCall'),
          onChanged: onChanged,
        ),
        if (conflictDays.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sp12),
          WarningNote(
            message: l10n.settings_availabilityConflict(
              _joinDayNames(context, conflictDays),
            ),
          ),
        ],
      ],
    );
  }

  /// Sunday-indexed labels, UNROTATED — [conflictDays] holds STORED indices and
  /// `weekdayAbbreviationsForLocale` is indexed the same way. Passing a
  /// display-ordered list here silently names the wrong day.
  String _joinDayNames(BuildContext context, Set<int> days) {
    final labels = weekdayAbbreviationsForLocale(
      Localizations.localeOf(context).toString(),
    );
    final ordered = days.toList()..sort();
    return ordered.map((index) => labels[index]).join(', ');
  }
}
