import 'package:scheduling/l10n/l10n.dart';

/// Validates the employee invite/edit form. Returns only the field keys that
/// have errors — an empty map means the form is valid.
class EmployeeFormValidator {
  const EmployeeFormValidator._();

  /// The name halves are taken separately, not as one composed name, because
  /// `composeEmployeeName` can never return empty — it falls back — so a
  /// composed value cannot express "the last name is missing". The first
  /// half's key stays `name`, which is what the first-name field reads.
  ///
  /// [requireLastName] mirrors the two sheets, which genuinely differ: an
  /// invite demands both halves (a roster row with nothing to identify is the
  /// failure mode), while an edit leaves the last name optional so a legacy
  /// single-name doc — whose whole stored name seeds First — still saves.
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
    if (email.trim().isEmpty) {
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
