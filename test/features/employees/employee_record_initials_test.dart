import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/employees/domain/models/employee_record.dart';

/// S4: `EmployeeRecord.initials` must tolerate weird whitespace so a
/// double-space name like 'Jane  Doe' doesn't throw RangeError on
/// `parts[1][0]`.
void main() {
  test('initials returns "?" for empty name', () {
    expect(const EmployeeRecord(id: '1').initials, '?');
  });

  test('initials uses single letter for single-word names', () {
    expect(const EmployeeRecord(id: '1', name: 'Jane').initials, 'J');
    expect(const EmployeeRecord(id: '1', name: 'cher').initials, 'C');
  });

  test('initials uses first letters of first two words', () {
    expect(const EmployeeRecord(id: '1', name: 'Jane Doe').initials, 'JD');
    expect(
      const EmployeeRecord(id: '1', name: 'Mary Ann Smith').initials,
      'MA',
    );
  });

  test('initials handles double spaces without crashing', () {
    // Pre-fix, `'Jane  Doe'.split(' ')` produced ['Jane', '', 'Doe'] and
    // `parts[1][0]` threw RangeError.
    expect(const EmployeeRecord(id: '1', name: 'Jane  Doe').initials, 'JD');
    expect(const EmployeeRecord(id: '1', name: '  Jane Doe').initials, 'JD');
    expect(const EmployeeRecord(id: '1', name: 'Jane Doe  ').initials, 'JD');
  });

  test('initials handles tabs and other whitespace', () {
    expect(const EmployeeRecord(id: '1', name: 'Jane\tDoe').initials, 'JD');
  });

  test('initials returns "?" when name is only whitespace', () {
    expect(const EmployeeRecord(id: '1', name: '   ').initials, '?');
  });
}
