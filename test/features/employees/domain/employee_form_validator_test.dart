import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/employees/domain/policies/employee_form_validator.dart';
import 'package:scheduling/l10n/l10n.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  Map<String, String?> validate({
    String firstName = '',
    String lastName = '',
    String email = '',
    bool requireLastName = false,
  }) {
    return EmployeeFormValidator.validate(
      l10n: l10n,
      firstName: firstName,
      lastName: lastName,
      email: email,
      requireLastName: requireLastName,
    );
  }

  group('EmployeeFormValidator', () {
    test('a name and an email produce no errors', () {
      expect(validate(firstName: 'Alex', email: 'alex@test.com'), isEmpty);
    });

    test('an empty name is flagged with the required message', () {
      final errors = validate(email: 'alex@test.com');
      expect(errors, hasLength(1));
      expect(errors['name'], l10n.error_nameAndEmailAreRequired);
    });

    test('an empty email is flagged with the required message', () {
      final errors = validate(firstName: 'Alex');
      expect(errors, hasLength(1));
      expect(errors['email'], l10n.error_nameAndEmailAreRequired);
    });

    test('both empty flags both fields', () {
      final errors = validate();
      expect(errors['name'], l10n.error_nameAndEmailAreRequired);
      expect(errors['email'], l10n.error_nameAndEmailAreRequired);
    });

    test('a blank last name is ignored unless the caller requires it', () {
      expect(validate(firstName: 'Alex', email: 'alex@test.com'), isEmpty);
    });

    test('the invite path flags a blank last name against its own field', () {
      final errors = validate(
        firstName: 'Alex',
        email: 'alex@test.com',
        requireLastName: true,
      );
      expect(errors, hasLength(1));
      expect(errors['lastName'], l10n.error_nameAndEmailAreRequired);
    });

    test('a whitespace-only last name does not satisfy the requirement', () {
      final errors = validate(
        firstName: 'Alex',
        lastName: '   ',
        email: 'alex@test.com',
        requireLastName: true,
      );
      expect(errors['lastName'], l10n.error_nameAndEmailAreRequired);
    });
  });
}
