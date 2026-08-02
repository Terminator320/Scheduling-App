import 'package:scheduling/l10n/l10n.dart';

/// Validates the employee invite/edit form. Returns only the field keys that
/// have errors — an empty map means the form is valid.
class EmployeeFormValidator {
  const EmployeeFormValidator._();

  static Map<String, String?> validate({
    required AppLocalizations l10n,
    required String name,
    required String email,
    int? workStartMinutes,
    int? workEndMinutes,
  }) {
    final errors = <String, String?>{};
    if (name.isEmpty) {
      errors['name'] = l10n.error_nameAndEmailAreRequired;
    }
    if (email.isEmpty) {
      errors['email'] = l10n.error_nameAndEmailAreRequired;
    }
    if (workStartMinutes != null &&
        workEndMinutes != null &&
        workEndMinutes <= workStartMinutes) {
      // Reuses the appointment form's existing string rather than adding a
      // second key that says the same thing. The `calendar_` prefix is an
      // organizing convention, not a boundary — a duplicate translation that
      // can drift is the worse outcome.
      errors['hours'] = l10n.calendar_mustBeAfterStartTime;
    }
    return errors;
  }
}
