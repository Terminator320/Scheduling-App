import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/calendar/domain/models/repeat_interval.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/fields/form_helpers.dart';

/// Localized label for a repeat interval — shared by the picker and the
/// read-only details view.
String repeatIntervalLabel(AppLocalizations l, RepeatInterval interval) =>
    switch (interval) {
      RepeatInterval.none => l.calendar_repeatNone,
      RepeatInterval.fourMonths => l.calendar_repeatEvery4Months,
      RepeatInterval.sixMonths => l.calendar_repeatEvery6Months,
      RepeatInterval.oneYear => l.calendar_repeatEveryYear,
    };

class RepeatIntervalPicker extends StatelessWidget {
  const RepeatIntervalPicker({
    required this.current,
    required this.onChanged,
    super.key,
  });

  final RepeatInterval current;
  final ValueChanged<RepeatInterval> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;

    return DropdownButtonFormField<RepeatInterval>(
      initialValue: current,
      decoration: formInputDecoration(context, repeatIntervalLabel(l, current)),
      borderRadius: BorderRadius.circular(AppRadius.r12),
      items: [
        for (final interval in RepeatInterval.values)
          DropdownMenuItem(
            value: interval,
            child: Text(repeatIntervalLabel(l, interval)),
          ),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}
