import 'package:scheduling/core/validators/auth_validators.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/l10n/l10n.dart';

// Shared validation for the add/edit forms. Values must already be trimmed, and
// contact errors are keyed by their list index.
class ClientFormValidator {
  const ClientFormValidator._();

  static Map<String, String?> validate({
    required AppLocalizations l10n,
    required String name,
    required String phone,
    required String mobile,
    required String email,
    required String address,
    required List<ClientContact> additionalContacts,
    String firstName = '',
    String lastName = '',
    bool noFixedAddress = false,
  }) {
    final errors = <String, String?>{
      // `name` is the only required field. Email has to be well-formed if provided;
      // phone/mobile aren't format-checked at all.
      'name': name.isEmpty ? l10n.validation_nameIsRequired : null,
      'email': _validateEmail(l10n, email),
      'address': (!noFixedAddress && address.isEmpty)
          ? l10n.validation_addressIsRequired
          : null,
    };

    for (var i = 0; i < additionalContacts.length; i++) {
      final contact = additionalContacts[i];
      // All-empty contact is ignored but consumes its index.
      if (contact.name.isEmpty &&
          contact.phone.isEmpty &&
          contact.email.isEmpty) {
        continue;
      }

      final hasAdditionalContactMethod =
          contact.phone.isNotEmpty || contact.email.isNotEmpty;
      errors['contact_${i}_name'] = contact.name.isEmpty
          ? l10n.validation_contactNameIsRequired
          : null;
      errors['contact_${i}_phone'] = !hasAdditionalContactMethod
          ? l10n.validation_phoneOrEmailIsRequired
          : null;
      errors['contact_${i}_email'] = _validateEmail(l10n, contact.email);
    }

    return errors;
  }

  static String? _validateEmail(AppLocalizations l10n, String email) {
    if (email.isEmpty) return null;
    if (!AuthValidators.isValidEmailFormat(email)) {
      return l10n.validation_enterAValidEmail;
    }
    return null;
  }
}
