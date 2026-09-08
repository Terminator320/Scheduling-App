import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/calendar/domain/holidays.dart';

/// The decoration of a day's number token, shared by every calendar surface
/// that renders one: the month grid, the collapsed week strip and the inline
/// date picker in the appointment form.
///
/// **Selection is a filled circle and today is a RING** (owner call,
/// 2026-08-14 — today used to be a blue number, which spoke the same language
/// as the picker/field accent, so "today" and "the value you picked" were
/// indistinguishable). The ring is `onSurface`, white on the dark theme and
/// ink on the light one, so it survives both; a literal white vanishes on the
/// light surface. **Selection wins** — a filled circle under a ring is noise.
///
/// This exists because the rule had three hand-written copies, two of them
/// carrying a comment asserting they matched the third. Changing the ring's
/// weight or colour then meant three identical edits, and the copies had
/// already drifted on the gate condition. Sizes and the number colour stay
/// with each cell: the three surfaces legitimately differ there, and only the
/// grid has a dot row beneath.
BoxDecoration calendarDayCircleDecoration({
  required ColorScheme scheme,
  required bool isSelected,
  required bool showTodayRing,
  Color? fill,
}) => BoxDecoration(
  shape: BoxShape.circle,
  color: isSelected ? scheme.primary : fill,
  border: showTodayRing && !isSelected
      ? Border.all(color: scheme.onSurface, width: 1.5)
      : null,
);

/// Finds the holiday rule in tests, on any of the three surfaces.
const Key calendarHolidayRuleKey = ValueKey('calendar-holiday-rule');

const double _kRuleWidth = 15;
const double _kRuleHeight = 2;

/// How far a kept hue is lifted toward `onPrimary` on a selected day.
///
/// Enough that all three clear 3:1 against the selection fill at this rule's
/// 2px — the WCAG bar for a non-text graphic — and no further, because every
/// step past that pulls the three hues toward the same white and costs the
/// category distinction the lift exists to preserve. Both themes make
/// `onPrimary` white over a saturated blue `primary`, so one factor serves
/// both and this needs no brightness branch.
const double _kSelectedHueLift = 0.6;

/// How far the rule sits above the token's bottom edge. Small enough to read
/// as an underline of the number rather than a separate mark, and clear of the
/// crew dot row that starts 3px BELOW the token.
const double _kRuleInset = 4;

/// The set's own hue, with no state applied — what the agenda row's rail
/// paints, and the base [holidayRuleColorFor] varies.
///
/// Read off the palette extension, never a `theme.brightness` branch — the
/// light/dark values belong on the extension (see the frontend rule), the way
/// `crewColorOf` reads `palette.crewOverride`.
Color holidayHueFor(ThemeData theme, HolidaySet set) => switch (set) {
  HolidaySet.statutory => theme.palette.holidayStatutory,
  HolidaySet.orthodox => theme.palette.holidayOrthodox,
  HolidaySet.construction => theme.palette.holidayConstruction,
};

/// The colour the holiday rule paints in, or null when [set] is null and the
/// day carries no holiday.
///
/// The number itself is never recoloured — the rule alone is the marker (owner
/// call, 2026-08-29) — so this is the only colour decision the feature makes.
///
/// Two variants, and the ORDER between them matters:
///
///  * **Selected wins**, in one of two ways. Any of the three hues muddies
///    against the primary-blue selection fill, and the Greek-blue candidate
///    this replaced was very nearly invisible on it. Where an agenda row sits
///    below — the month grid and the week strip, where the row is open by
///    definition on a selected day — the rule simply goes `onPrimary` and the
///    row carries the colour and the name. Where there is NO row below, pass
///    [keepHueWhenSelected]: the hue is lifted toward `onPrimary` instead of
///    replaced by it, so the day still says WHICH kind of holiday it is.
///  * **Faint** (an off-month cell) drops the alpha so the rule fades with the
///    number rather than shouting from a cell that is deliberately recessed.
///    This is the NORMAL case for the construction shutdown, which crosses the
///    July/August boundary every single year.
Color? holidayRuleColorFor({
  required ThemeData theme,
  required HolidaySet? set,
  required bool isSelected,
  required bool isFaint,
  bool keepHueWhenSelected = false,
}) {
  if (set == null) return null;
  final hue = holidayHueFor(theme, set);
  if (isSelected) {
    return keepHueWhenSelected
        ? Color.lerp(hue, theme.colorScheme.onPrimary, _kSelectedHueLift)!
        : theme.colorScheme.onPrimary;
  }
  return isFaint ? hue.withValues(alpha: 0.45) : hue;
}

/// Overlays [set]'s holiday rule on a day [token], or returns it untouched on
/// an ordinary day.
///
/// It resolves the colour itself rather than taking one, so a day-token surface
/// cannot render the token and forget the marker — the failure that would
/// compile clean and simply show nothing. That is the drift
/// [calendarDayCircleDecoration] was extracted to end, and this is its twin.
///
/// [keepHueWhenSelected] is for a surface with no agenda row beneath it — see
/// [holidayRuleColorFor]. The form's `InlineMonthCalendar` is the one that
/// passes it.
///
/// Wraps the token rather than becoming its child: the rule has to sit a fixed
/// distance from the token's BOTTOM edge, and a child is centred on the number,
/// which is shorter than the circle and shifts with the font metrics.
///
/// Painting inside the circle is the whole design. A marker living in the
/// token's `fill` is erased by selection — which wins the fill by rule in
/// [calendarDayCircleDecoration] — so it would be absent on exactly the day
/// being read. One owner for all three surfaces that draw a day token: the
/// month grid, the collapsed week strip, and the form's `InlineMonthCalendar`.
Widget calendarDayTokenWithRule({
  required Widget token,
  required HolidaySet? set,
  required bool isSelected,
  required bool isFaint,
  required ThemeData theme,
  bool keepHueWhenSelected = false,
}) {
  final ruleColor = holidayRuleColorFor(
    theme: theme,
    set: set,
    isSelected: isSelected,
    isFaint: isFaint,
    keepHueWhenSelected: keepHueWhenSelected,
  );
  if (ruleColor == null) return token;
  return Stack(
    alignment: Alignment.bottomCenter,
    children: [
      token,
      Padding(
        padding: const EdgeInsets.only(bottom: _kRuleInset),
        child: Container(
          key: calendarHolidayRuleKey,
          width: _kRuleWidth,
          height: _kRuleHeight,
          decoration: BoxDecoration(
            color: ruleColor,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ),
    ],
  );
}
