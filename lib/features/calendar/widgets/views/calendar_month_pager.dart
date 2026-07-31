import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/calendar/widgets/views/calendar_month_grid.dart';

/// Month index anchored far enough back that no realistic booking underflows.
const int _kBaseYear = 2000;

int _pageForMonth(DateTime month) =>
    (month.year - _kBaseYear) * 12 + (month.month - 1);

DateTime _monthForPage(int page) =>
    DateTime(_kBaseYear + page ~/ 12, page % 12 + 1);

/// Horizontal month paging. The custom grid owns this because `table_calendar`
/// used to — and the hub's iOS edge-swipe deliberately exempts the calendar tab
/// so these drags aren't stolen.
class CalendarMonthPager extends StatefulWidget {
  const CalendarMonthPager({
    required this.month,
    required this.selectedDay,
    required this.today,
    required this.onDaySelected,
    required this.onMonthChanged,
    required this.dotColorsFor,
    required this.countFor,
    super.key,
  });

  final DateTime month;
  final DateTime selectedDay;
  final DateTime today;
  final ValueChanged<DateTime> onDaySelected;
  final ValueChanged<DateTime> onMonthChanged;
  final List<Color> Function(DateTime day) dotColorsFor;
  final int Function(DateTime day) countFor;

  @override
  State<CalendarMonthPager> createState() => _CalendarMonthPagerState();
}

class _CalendarMonthPagerState extends State<CalendarMonthPager> {
  late final PageController _controller = PageController(
    initialPage: _pageForMonth(widget.month),
  );

  @override
  void didUpdateWidget(CalendarMonthPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.month == oldWidget.month) return;
    // The month also changes from the picker and the Today pill; jump the pager
    // to match without re-notifying the parent. It has to wait for the frame:
    // jumpToPage mutates scroll state, and didUpdateWidget runs mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncToMonth());
  }

  void _syncToMonth() {
    if (!mounted || !_controller.hasClients) return;
    // Re-read the month rather than capturing it, so a burst of changes settles
    // on the latest one.
    final target = _pageForMonth(widget.month);
    if (_controller.page?.round() == target) return;
    _controller.jumpToPage(target);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Months occupy 4–6 weeks, so the viewport height follows the month in
    // view. It animates because `onPageChanged` fires mid-settle: a hard jump
    // there would snap the agenda below by a whole row.
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppMotion.riseInShort,
      curve: AppMotion.emphasized,
      height: CalendarMonthGrid.heightFor(
        context,
        rows: CalendarMonthGrid.rowsFor(context, widget.month),
      ),
      child: PageView.builder(
        controller: _controller,
        onPageChanged: (page) {
          final month = _monthForPage(page);
          // A programmatic jump fires this too. Echoing the parent's own change
          // back would reset its focused day to the 1st of the month.
          if (month.year == widget.month.year &&
              month.month == widget.month.month) {
            return;
          }
          widget.onMonthChanged(month);
        },
        // Until the height settles on the new month, the page being dragged in
        // may need one row more than the viewport has. Let it lay out at its
        // natural height, pinned to the top, and clip the difference — a plain
        // page would overflow for the length of the drag.
        itemBuilder: (context, page) => ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: 0,
            maxHeight: double.infinity,
            child: CalendarMonthGrid(
              month: _monthForPage(page),
              selectedDay: widget.selectedDay,
              today: widget.today,
              onDaySelected: widget.onDaySelected,
              dotColorsFor: widget.dotColorsFor,
              countFor: widget.countFor,
            ),
          ),
        ),
      ),
    );
  }
}
