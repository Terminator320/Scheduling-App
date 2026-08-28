import 'package:scheduling/core/validators/auth_validators.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Validates the employee invite/edit form.
class EmployeeFormValidator {
  const EmployeeFormValidator._();

  /// Returns field-error keys, with [requireLastName] matching invite-only rules.
  static Map<String, String?> validate({
    required AppLocalizations l10n,
    required String firstName,
    required String lastName,
    required String email,
    bool requireLastName = false,
    int? workStartMinutes,
    int? workEndMinutes,
  }) {
    final errors = <String, String?>{};
    if (firstName.trim().isEmpty) {
      errors['name'] = l10n.error_nameAndEmailAreRequired;
    }
    if (requireLastName && lastName.trim().isEmpty) {
      errors['lastName'] = l10n.error_nameAndEmailAreRequired;
    }
    final trimmedEmail = email.trim();
    if (trimmedEmail.isEmpty) {
      errors['email'] = l10n.error_nameAndEmailAreRequired;
    } else if (!AuthValidators.isValidEmailFormat(trimmedEmail)) {
      errors['email'] = l10n.validation_pleaseEnterAValidEmailAddress;
    }
    if (workStartMinutes != null &&
        workEndMinutes != null &&
        workEndMinutes <= workStartMinutes) {
      // Reuse the appointment form's existing start/end validation string.
      errors['hours'] = l10n.calendar_mustBeAfterStartTime;
    }
    return errors;
  }
}
