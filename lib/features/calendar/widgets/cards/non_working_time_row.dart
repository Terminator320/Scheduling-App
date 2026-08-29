/// The chrome the agenda's NON-WORKING-TIME rows share — a booked day off
/// (`_DayOffStrip`, `appointment_card.dart`) and a holiday
/// (`HolidayAgendaRow`, `views/holiday_agenda_row.dart`).
///
/// The two say the same kind of thing — "this day is not work" — so they wear
/// the same ground, and a holiday joining that vocabulary rather than opening
/// its own is deliberate. What is shared here is only what must never drift
/// between them: the ground itself, the row's minimum height, the rail width,
/// and the headline-over-caption column. Each row keeps its own LAYOUT, which
/// legitimately differs — the day off positions a dashed rail in a `Stack` to
/// avoid forcing intrinsic layout and carries an avatar, while a holiday
/// belongs to nobody, so its rail is an ordinary solid child of the row.
///
/// This was two hand-written copies until 2026-08-29, and they had already
/// drifted on the caption gap before the second one shipped.
library;

import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';

/// Minimum height of a non-working-time row — Material's touch target, and
/// these rows are tappable (the day off opens its detail sheet).
const double kNonWorkingRowMinHeight = 44;

/// The leading rail's width, dashed on a day off and solid on a holiday.
const double kNonWorkingRailWidth = 3;

/// Gap between the headline and its caption.
const double _kCaptionGap = 3;

/// The ground a non-working-time row sits on.
///
/// **The border is load-bearing, not decoration**: `neutralContainer` resolves
/// to `AppColors.paper`, which is ALSO `scaffoldBackgroundColor`, so without an
/// edge the row has no visible container at all in the light theme. It is also
/// what separates two of these rows stacked on the same day.
BoxDecoration nonWorkingTimeDecoration(ThemeData theme) => BoxDecoration(
  color: theme.statusColors.neutralContainer,
  borderRadius: BorderRadius.circular(AppRadius.r12),
  border: Border.all(color: theme.colorScheme.outline),
);

/// The headline-over-caption column in a non-working-time row's middle slot.
///
/// **The headline slot is ALWAYS filled and only [caption] is conditional** —
/// never render both slots from the same string. On a day off that means the
/// typed reason when there is one and the `<name> is off` sentence when there
/// isn't; on a holiday, the holiday's name with its set beneath.
class NonWorkingTimeText extends StatelessWidget {
  const NonWorkingTimeText({
    required this.headline,
    required this.caption,
    super.key,
    this.isMuted = false,
    this.headlineMaxLines = 1,
  });

  final String headline;

  /// The second line, or null when the headline says everything.
  final String? caption;

  /// A finished day off recedes; a holiday never does.
  final bool isMuted;

  /// Two for a holiday, whose names run long ("Journée nationale des
  /// patriotes"); one for a day off, which is a short sentence about a person.
  final int headlineMaxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caption = this.caption;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          headline,
          maxLines: headlineMaxLines,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            color: isMuted ? theme.palette.textTertiary : theme.palette.textBody,
          ),
        ),
        if (caption != null) ...[
          const SizedBox(height: _kCaptionGap),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.palette.textTertiary,
            ),
          ),
        ],
      ],
    );
  }
}
