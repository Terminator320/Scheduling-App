import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';

/// The shell every custom `Dialog` in the app shares: inset, rounded shape,
/// `sp24` padding and a min-height start-aligned column.
///
/// Extracted from the only three `return Dialog(` sites in `lib/`
/// (`busy_conflict_dialog`, `personal_block_clash_dialog`,
/// `series_scope_dialog`), which repeated the same twelve lines verbatim —
/// including the raw `26` horizontal inset, which is the one value here with
/// no token behind it.
///
/// `showConfirmDialog` is deliberately NOT built on this: it is an
/// `AlertDialog` with a Cupertino variant, a different shape entirely.
class AppDialogFrame extends StatelessWidget {
  const AppDialogFrame({required this.children, super.key});

  /// Laid out in a `MainAxisSize.min`, `CrossAxisAlignment.start` column.
  final List<Widget> children;

  /// Deliberately raw and deliberately shared: it sits between `sp24` and
  /// `sp32`, so a token would have to be invented for one measurement. Spelled
  /// once here rather than three times at the call sites.
  static const double _horizontalInset = 26;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: _horizontalInset,
        vertical: AppSpacing.sp24,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.rDialog),
      ),
      // The body SCROLLS, and that is not belt-and-braces. `Dialog` hands its
      // child the viewport height minus the insets, and a bare `Column` there
      // overflows rather than scrolling — at 260 logical px with 2x text every
      // dialog built on this frame ran off the bottom (the series-scope one by
      // 178px, before this frame gained a single new caller). These dialogs
      // stack a title, two radio options with a consequence line each and an
      // action row, so they are the tallest custom surfaces in the app and the
      // first to go over.
      //
      // `MainAxisSize.min` stays on the column: the scroll view sizes to its
      // child, so a short dialog is still short and only a tall one scrolls.
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.sp24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}
