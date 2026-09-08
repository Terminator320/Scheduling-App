import 'package:flutter/material.dart';

import 'package:scheduling/core/adaptive/adaptive_action_sheet.dart';
import 'package:scheduling/features/calendar/domain/models/repeat_interval.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/fields/sheet_field_row.dart';

/// Localized label for a repeat interval (shared by picker and details view).
String repeatIntervalLabel(AppLocalizations l, RepeatInterval interval) =>
    switch (interval) {
      RepeatInterval.none => l.calendar_repeatNone,
      RepeatInterval.fourMonths => l.calendar_repeatEvery4Months,
      RepeatInterval.sixMonths => l.calendar_repeatEvery6Months,
      RepeatInterval.oneYear => l.calendar_repeatEveryYear,
    };

/// The repeat rule as a panel row, so it sits in the same `SheetPanel` as the
/// date and the times — one grouped block for everything about *when* the job
/// happens (owner call, 2026-07-31). It was a standalone dropdown below the
/// panel, which read as an unrelated field.
class RepeatIntervalPicker extends StatelessWidget {
  const RepeatIntervalPicker({
    required this.current,
    required this.onChanged,
    super.key,
  });

  final RepeatInterval current;
  final ValueChanged<RepeatInterval> onChanged;

  Future<void> _pick(BuildContext context) async {
    final l = context.l10n;
    final picked = await showAdaptiveActionSheet<RepeatInterval>(
      context,
      title: l.calendar_repeat,
      actions: [
        for (final interval in RepeatInterval.values)
          AdaptiveSheetAction(
            value: interval,
            label: repeatIntervalLabel(l, interval),
          ),
      ],
    );
    if (picked == null || !context.mounted) return;
    onChanged(picked);
  }

  @override
  Widget build(BuildContext context) => SheetFieldRow(
    label: context.l10n.calendar_repeat,
    value: repeatIntervalLabel(context.l10n, current),
    accent: current != RepeatInterval.none,
    onTap: () => _pick(context),
    trailing: const Icon(Icons.repeat, size: 18),
  );
}
