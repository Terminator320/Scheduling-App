import 'package:scheduling/l10n/l10n.dart';

/// Validation for employee invite/edit form; returns only offending field keys (empty = valid).
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
