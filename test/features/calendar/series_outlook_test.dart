import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/calendar/application/event_series_helpers.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

AppointmentRecord _at(DateTime start, {String status = 'pending'}) =>
    AppointmentRecord(
      id: start.toIso8601String(),
      title: 'Job',
      startTime: start,
      endTime: start.add(const Duration(hours: 1)),
      status: status,
      seriesId: 's1',
    );

AppointmentRecord _runDay(DateTime start, {required int dayIndex}) =>
    _at(start).copyWith(dayIndex: dayIndex, dayCount: 5, seriesId: 'run');

void main() {
  final series = [
    _at(DateTime(2026, 1, 5)),
    _at(DateTime(2026, 1, 19)),
    _at(DateTime(2026, 2, 2)),
    _at(DateTime(2026, 2, 16)),
  ];

  ({int count, DateTime? last}) outlookAt(
    List<AppointmentRecord> from,
    AppointmentRecord anchor,
  ) => seriesOutlook(from, anchor: anchor, excludeId: anchor.id ?? '');

  test('counts this occurrence and every later one', () {
    final outlook = outlookAt(series, series[1]);
    expect(outlook.count, 3);
    expect(outlook.last, DateTime(2026, 2, 16));
  });

  test('the first occurrence sees the whole series', () {
    expect(outlookAt(series, series[0]).count, 4);
  });

  test('the last occurrence sees only itself', () {
    final outlook = outlookAt(series, series[3]);
    expect(outlook.count, 1);
    expect(outlook.last, DateTime(2026, 2, 16));
  });

  test('an unsorted series still reports the true last date', () {
    final shuffled = [series[2], series[0], series[3], series[1]];
    expect(outlookAt(shuffled, series[0]).last, DateTime(2026, 2, 16));
  });

  // The two divergences that made the dialog's number disagree with the write.
  test('a terminal sibling is not counted, because it is not written', () {
    final withCancelled = [
      series[0],
      _at(DateTime(2026, 1, 19), status: 'cancelled'),
      series[2],
    ];
    // Three occurrences from the first, but the cancelled one is never
    // written — the button used to say "Save 3 visits" and write 2.
    expect(outlookAt(withCancelled, series[0]).count, 2);
  });

  test('a RUN is scoped by dayIndex, like the write', () {
    // Day 1 was moved out past the rest of the run, so the two axes disagree.
    final run = [
      _runDay(DateTime(2026, 8, 10), dayIndex: 1),
      _runDay(DateTime(2026, 8, 2), dayIndex: 2),
      _runDay(DateTime(2026, 8, 3), dayIndex: 3),
    ];
    // From day 1: itself plus days 2 and 3, even though neither starts later.
    expect(outlookAt(run, run[0]).count, 3);
    // From day 3: only itself — day 1 sits later in TIME but earlier in the
    // run, and counting on startTime swept it in.
    expect(outlookAt(run, run[2]).count, 1);
  });
}
