import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/shared/widgets/primitives/section_label.dart';

/// The pinned `AUGUST 2026` bar that opens each month's run of History rows.
///
/// **Sticky is load-bearing at the boundary, not decoration.** Crossing from
/// August into July the day numbers on the rail reset from 3 back to 31; with
/// no header on screen announcing the month, that reads as a data error rather
/// than a transition.
///
/// It replaces BOTH of the old headers — the bold year separator and the
/// per-day `SectionLabel`. The month already carries the year, and the day now
/// lives on the rail, so keeping either would be a third heading repeating the
/// second.
class HistoryMonthBar extends SliverPersistentHeaderDelegate {
  HistoryMonthBar({required this.label, required this.extent});

  /// Formatted by the caller through `monthYearFormatFor`, which is memoized
  /// per locale — a `DateFormat` constructor must never run inside a builder.
  final String label;

  /// Measured by the caller against the text scaler. A persistent header's
  /// extent is a number, not a layout, so it cannot discover its own height.
  final double extent;

  /// The bar's height at scale 1, before the text scaler is applied.
  static const double baseExtent = 34;

  /// Sized against the label, not the row: this bar is text on the page's own
  /// background rather than a filled chip, so its height is the label's line
  /// box plus the padding above and below it.
  static double extentFor(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(baseExtent);

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // Opaque on purpose — pinned, it scrolls over the rows beneath it, and the
    // scaffold colour is what those rows sit on.
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sp8),
          child: SectionLabel(label),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant HistoryMonthBar oldDelegate) =>
      oldDelegate.label != label || oldDelegate.extent != extent;
}
