import 'package:flutter/widgets.dart';

/// Focus-management helpers that encode the CLAUDE.md "sheet-from-search"
/// timing invariant in one place:
///
/// > 80 ms settle before `showModalBottomSheet`; double unfocus with a
/// > 120 ms gap after the sheet closes.
///
/// Callers should `await SheetFocus.settleBeforeSheet()` immediately before
/// opening a modal sheet from a `TextField` (otherwise the keyboard fights
/// focus on the way in), and `await SheetFocus.unfocusAfterSheet()` right
/// after the sheet closes (otherwise the search field snaps focus back and
/// re-shows the keyboard).
///
/// Both helpers operate on the global `FocusManager` so they remain valid
/// even if the calling State has unmounted mid-await; callers should still
/// check `mounted` before touching `setState` or `BuildContext` afterwards.
class SheetFocus {
  const SheetFocus._();

  static Future<void> settleBeforeSheet() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }

  static Future<void> unfocusAfterSheet() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    FocusManager.instance.primaryFocus?.unfocus();
  }
}
