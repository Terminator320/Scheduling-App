import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/employees/domain/policies/employee_name_policy.dart';

void main() {
  group('composeEmployeeName', () {
    test('joins first and last', () {
      expect(
        composeEmployeeName(firstName: 'Theo', lastName: 'Roy', fallback: 'x'),
        'Theo Roy',
      );
    });

    test('uses whichever half is present', () {
      expect(
        composeEmployeeName(firstName: 'Theo', lastName: '', fallback: 'x'),
        'Theo',
      );
      expect(
        composeEmployeeName(firstName: '  ', lastName: 'Roy', fallback: 'x'),
        'Roy',
      );
    });

    test('falls back to the stored name when both halves are empty', () {
      expect(
        composeEmployeeName(
          firstName: '',
          lastName: '  ',
          fallback: 'Legacy Name',
        ),
        'Legacy Name',
      );
    });

    // The whole point of the helper: watchAllUsers orders by `name`, and
    // Firestore drops docs missing the orderBy field.
    test('never returns empty, even with an empty fallback', () {
      expect(
        composeEmployeeName(firstName: '', lastName: '', fallback: '   '),
        '—',
      );
    });
  });
}
