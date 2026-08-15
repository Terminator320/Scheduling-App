import 'package:flutter/material.dart';

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
