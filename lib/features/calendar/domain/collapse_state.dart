/// Scroll thresholds for the calendar's month-grid collapse
/// (`03-screens-schedule.md`). Held apart from the widget so the anti-thrash
/// rule is testable without a scroll view.
class CalendarCollapse {
  /// Past this offset the month grid unmounts and the week strip rises.
  static const double collapseAt = 80;

  /// Scrolling back *below* this arms the re-expansion…
  static const double rearmAt = 44;

  /// …which then fires below here. Collapsing at 80 and expanding at 6 is
  /// already 74px of hysteresis; the arm stage is what stops a scroll that
  /// merely hovers the collapse threshold from flickering the grid.
  static const double expandBelow = 6;

  bool get isCollapsed => _collapsed;
  bool _collapsed = false;
  bool _armed = false;

  /// Feeds a new scroll offset. Returns true when the collapsed flag flipped —
  /// the caller rebuilds only on a transition, never per scroll frame.
  bool onOffset(double offset) {
    if (!_collapsed) {
      if (offset <= collapseAt) return false;
      _collapsed = true;
      _armed = false;
      return true;
    }
    // Both stages are evaluated in one pass so a jumpTo(0) — which skips every
    // intermediate frame — still re-expands.
    if (offset < rearmAt) _armed = true;
    if (!_armed || offset >= expandBelow) return false;
    _collapsed = false;
    return true;
  }
}
