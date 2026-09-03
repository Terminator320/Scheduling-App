import 'package:flutter/widgets.dart';
import 'package:scheduling/features/clients/domain/policies/client_contacts_policy.dart';
import 'package:scheduling/features/clients/widgets/sections/additional_contacts_section.dart';

/// Shared form-state plumbing for the add/edit forms. Remember to call
/// disposeAdditionalContacts from dispose.
mixin ClientFormState<T extends StatefulWidget> on State<T> {
  /// Field key -> error message (null when valid). Drives the field errorText.
  final Map<String, String?> errors = {};

  /// Extra business contacts beyond the primary name/phone/email.
  final List<ContactFields> additionalContacts = [];

  /// True if the client has no stored address. Set per appointment.
  bool noFixedAddress = false;

  /// Toggles [noFixedAddress]; clears any stale address error when enabling.
  void setNoFixedAddress({required bool value}) {
    setState(() {
      noFixedAddress = value;
      if (value) errors['address'] = null;
    });
  }

  /// Clears the error for [key] (and rebuilds) if one is currently set.
  void clearError(String key) {
    if (errors[key] != null) setState(() => errors[key] = null);
  }

  void addAdditionalContact() {
    if (additionalContacts.length >= kMaxAdditionalContacts) return;
    setState(() => additionalContacts.add(ContactFields()));
  }

  void removeAdditionalContact(int index) {
    setState(() {
      additionalContacts.removeAt(index).dispose();
      // Later rows shift index; form rebuilds all contact_ keys.
      errors
        ..remove('contact_${index}_name')
        ..remove('contact_${index}_phone')
        ..remove('contact_${index}_email');
    });
  }

  /// Disposes every additional-contact controller. Call from the State's
  /// `dispose` before `super.dispose()`.
  void disposeAdditionalContacts() {
    for (final contact in additionalContacts) {
      contact.dispose();
    }
  }
}
