import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/employees/domain/policies/employee_form_validator.dart';
import 'package:scheduling/l10n/l10n.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  Map<String, String?> validate({String name = '', String email = ''}) {
    return EmployeeFormValidator.validate(l10n: l10n, name: name, email: email);
  }

  group('EmployeeFormValidator', () {
    test('a name and an email produce no errors', () {
      expect(validate(name: 'Alex', email: 'alex@test.com'), isEmpty);
    });

    test('an empty name is flagged with the required message', () {
      final errors = validate(email: 'alex@test.com');
      expect(errors, hasLength(1));
      expect(errors['name'], l10n.error_nameAndEmailAreRequired);
    });

    test('an empty email is flagged with the required message', () {
      final errors = validate(name: 'Alex');
      expect(errors, hasLength(1));
      expect(errors['email'], l10n.error_nameAndEmailAreRequired);
    });

    test('both empty flags both fields', () {
      final errors = validate();
      expect(errors['name'], l10n.error_nameAndEmailAreRequired);
      expect(errors['email'], l10n.error_nameAndEmailAreRequired);
    });
  });
}
