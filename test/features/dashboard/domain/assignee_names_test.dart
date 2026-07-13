import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/dashboard/domain/assignee_names.dart';

AppointmentRecord _appt({
  List<String> employeeIds = const [],
  List<String> employeeNames = const [],
}) => AppointmentRecord(
  id: 'a1',
  title: 'Job',
  startTime: DateTime(2026, 7, 8, 12),
  endTime: DateTime(2026, 7, 8, 13),
  employeeIds: employeeIds,
  employeeNames: employeeNames,
);

void main() {
  group('resolveAssigneeNames', () {
    test('joins names resolved from the live name map', () {
      final result = resolveAssigneeNames(
        _appt(employeeIds: ['e1', 'e2']),
        {'e1': 'Jane', 'e2': 'Marc'},
      );
      expect(result, 'Jane, Marc');
    });

    test('drops ids missing from the map, keeping the ones present', () {
      final result = resolveAssigneeNames(
        _appt(employeeIds: ['e1', 'gone']),
        {'e1': 'Jane'},
      );
      expect(result, 'Jane');
    });

    test('falls back to denormalized employeeNames when none resolve', () {
      final result = resolveAssigneeNames(
        _appt(employeeIds: ['gone'], employeeNames: ['Old Name']),
        {'e1': 'Jane'},
      );
      expect(result, 'Old Name');
    });

    test('returns null when no name is known from either source', () {
      final result = resolveAssigneeNames(
        _appt(employeeIds: ['gone']),
        {'e1': 'Jane'},
      );
      expect(result, isNull);
    });
  });
}
