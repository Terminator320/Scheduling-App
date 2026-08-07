import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/domain/series_outlook.dart';

AppointmentRecord _at(DateTime start) => AppointmentRecord(
  id: start.toIso8601String(),
  title: 'Job',
  startTime: start,
  endTime: start.add(const Duration(hours: 1)),
  seriesId: 's1',
);

void main() {
  final series = [
    _at(DateTime(2026, 1, 5)),
    _at(DateTime(2026, 1, 19)),
    _at(DateTime(2026, 2, 2)),
    _at(DateTime(2026, 2, 16)),
  ];

  test('counts this occurrence and every later one', () {
    final outlook = seriesOutlook(series, DateTime(2026, 1, 19));
    expect(outlook.count, 3);
    expect(outlook.last, DateTime(2026, 2, 16));
  });

  test('the first occurrence sees the whole series', () {
    expect(seriesOutlook(series, DateTime(2026, 1, 5)).count, 4);
  });

  test('the last occurrence sees only itself', () {
    final outlook = seriesOutlook(series, DateTime(2026, 2, 16));
    expect(outlook.count, 1);
    expect(outlook.last, DateTime(2026, 2, 16));
  });

  test('an unsorted series still reports the true last date', () {
    final shuffled = [series[2], series[0], series[3], series[1]];
    expect(
      seriesOutlook(shuffled, DateTime(2026, 1, 5)).last,
      DateTime(2026, 2, 16),
    );
  });

  test('an empty series reports nothing', () {
    final outlook = seriesOutlook(const [], DateTime(2026, 1, 5));
    expect(outlook.count, 0);
    expect(outlook.last, isNull);
  });
}
