import 'package:scheduling/l10n/l10n.dart';

/// Shared validation for the employee invite/edit form (mirrors
/// `ClientFormValidator`). All field values must be pre-trimmed. Returns only
/// the offending field keys, so an empty map means the form is valid.
class EmployeeFormValidator {
  const EmployeeFormValidator._();

  static Map<String, String?> validate({
    required AppLocalizations l10n,
    required String name,
    required String email,
  }) {
    final errors = <String, String?>{};
    if (name.isEmpty) {
      errors['name'] = l10n.error_nameAndEmailAreRequired;
    }
    if (email.isEmpty) {
      errors['email'] = l10n.error_nameAndEmailAreRequired;
    }
    return errors;
  }
}
