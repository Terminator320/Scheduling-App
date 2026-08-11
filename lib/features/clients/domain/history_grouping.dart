import 'package:scheduling/features/calendar/domain/appointment_status_values.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

/// A contiguous run of history rows that fall in the same calendar month.
///
/// A window into the flat list rather than a copy of it: `start` is the index
/// of the section's first row in that list, which is what lets the list keep
/// ONE global index. The feature tour wraps row 0 and the pager prefetches near
/// the end, and both ask about the whole list, not about a section of it.
typedef HistoryMonthSection = ({DateTime month, int start, int length});

/// The list's own tally — `cancelled` is a SUBSET of `total`, never an
/// addition, the same shape as the calendar agenda's `4 JOBS · 1 DONE`.
typedef HistoryTally = ({int total, int cancelled});

/// Splits [rows] into month sections, in the order they already appear.
///
/// Never re-sorts. History is served newest-first by the query and a search
/// result set keeps whatever order the repository returned, so a section is a
/// contiguous RUN and not a bucket — a month the list somehow re-entered later
/// would open a second section rather than silently reordering the rows above
/// it.
List<HistoryMonthSection> monthSectionsOf(List<AppointmentRecord> rows) {
  final sections = <HistoryMonthSection>[];
  var start = 0;
  for (var i = 1; i <= rows.length; i++) {
    final ends = i == rows.length || !_sameMonth(rows[i], rows[start]);
    if (!ends) continue;
    sections.add((
      month: _monthOf(rows[start].startTime),
      start: start,
      length: i - start,
    ));
    start = i;
  }
  return sections;
}

/// True when [index] opens a new day, which is when the date rail carries a
/// date instead of leaving its column empty.
///
/// Repeating the date beside every row of a busy day is noise; the rail still
/// reserves its width, so the cards stay aligned.
bool startsDay(List<AppointmentRecord> rows, int index) {
  if (index == 0) return true;
  return !_sameDay(rows[index - 1].startTime, rows[index].startTime);
}

/// Counts the rows on screen and how many of them were called off.
///
/// Deliberately over the RENDERED rows: History is paginated, so this is
/// honest about the list you are looking at. A per-month count could only ever
/// report what had loaded, which is a figure that climbs while you read it —
/// which is why there are none.
HistoryTally tallyOf(List<AppointmentRecord> rows) => (
  total: rows.length,
  cancelled: rows.where((a) => isCancelledStatusRaw(a.status)).length,
);

/// The two statuses History actually holds — the `terminalStatusRawValues` set
/// — offered as quick-filter chips. Anything richer would need a field the
/// record does not carry.
enum HistoryStatusFilter {
  complete,
  cancelled;

  bool matches(AppointmentRecord appointment) => switch (this) {
    complete => isCompletedStatusRaw(appointment.status),
    cancelled => isCancelledStatusRaw(appointment.status),
  };
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool _sameMonth(AppointmentRecord a, AppointmentRecord b) =>
    a.startTime.year == b.startTime.year &&
    a.startTime.month == b.startTime.month;

DateTime _monthOf(DateTime date) => DateTime(date.year, date.month);
