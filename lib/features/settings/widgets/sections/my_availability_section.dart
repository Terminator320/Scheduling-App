import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/calendar/domain/month_grid.dart';
import 'package:scheduling/features/employees/domain/policies/work_schedule_policy.dart';
import 'package:scheduling/features/employees/widgets/fields/working_days_picker.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/cards/sheet_panel.dart';
import 'package:scheduling/shared/widgets/cards/sheet_panel_row.dart';
import 'package:scheduling/shared/widgets/feedback/warning_note.dart';
import 'package:scheduling/shared/widgets/fields/sheet_field_row.dart';
import 'package:scheduling/shared/widgets/primitives/mono_section_label.dart';

/// Signature of an availability edit.
///
/// Every value travels together so the write is ONE patch: the rules' `hasOnly`
/// is satisfied by the key set, not by which of them actually changed, so
/// sending a partial patch would buy nothing and fork the save path.
typedef AvailabilityChanged =
    void Function(
      List<bool> workingDays,
      int workStartMinutes,
      int workEndMinutes, {
      required bool onCall,
    });

/// Day toggles, hours and on-call — **applied immediately** (P5 spec).
///
/// Deliberately unlike the identity section above it, which is explicitly
/// saved. These are switches: one that needs a second confirmation reads as
/// broken, and the write is a single allowlisted patch that cannot half-apply.
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
    final materialL10n = MaterialLocalizations.of(context);

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
        SheetPanel(
          children: [
            SheetPanelRow(
              label: l10n.employees_workingDays,
              child: WorkingDaysPicker(
                workingDays: workingDays,
                onChanged: (next) => onChanged(
                  next,
                  workStartMinutes,
                  workEndMinutes,
                  onCall: onCall,
                ),
              ),
            ),
            SheetFieldRow(
              label: l10n.employees_startsAt,
              value: materialL10n.formatTimeOfDay(
                minutesToTimeOfDay(workStartMinutes),
              ),
              onTap: () => _pickTime(
                context,
                initial: workStartMinutes,
                onPicked: (minutes) => onChanged(
                  workingDays,
                  minutes,
                  workEndMinutes,
                  onCall: onCall,
                ),
              ),
            ),
            SheetFieldRow(
              label: l10n.employees_endsAt,
              value: materialL10n.formatTimeOfDay(
                minutesToTimeOfDay(workEndMinutes),
              ),
              onTap: () => _pickTime(
                context,
                initial: workEndMinutes,
                onPicked: (minutes) => onChanged(
                  workingDays,
                  workStartMinutes,
                  minutes,
                  onCall: onCall,
                ),
              ),
            ),
            SheetPanelRow(
              label: l10n.employees_onCall,
              trailing: Switch.adaptive(
                key: const Key('myOnCall'),
                value: onCall,
                activeTrackColor: theme.colorScheme.primary,
                onChanged: (value) => onChanged(
                  workingDays,
                  workStartMinutes,
                  workEndMinutes,
                  onCall: value,
                ),
              ),
            ),
          ],
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

  Future<void> _pickTime(
    BuildContext context, {
    required int initial,
    required ValueChanged<int> onPicked,
  }) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: minutesToTimeOfDay(initial),
    );
    if (picked == null) return;
    onPicked(picked.hour * 60 + picked.minute);
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
