import 'package:flutter/widgets.dart';
import 'package:scheduling/features/clients/widgets/sections/additional_contacts_section.dart';

/// Shared form-state plumbing for the add- and edit-client forms: the field
/// [errors] map and the list of [additionalContacts], plus the mutators both
/// forms had duplicated. Mix into the form's [State].
///
/// The owning State must call [disposeAdditionalContacts] from its `dispose`.
mixin ClientFormState<T extends StatefulWidget> on State<T> {
  /// Field key -> error message (null when valid). Drives the field errorText.
  final Map<String, String?> errors = {};

  /// Extra business contacts beyond the primary name/phone/email.
  final List<ContactFields> additionalContacts = [];

  /// Clears the error for [key] (and rebuilds) if one is currently set.
  void clearError(String key) {
    if (errors[key] != null) setState(() => errors[key] = null);
  }

  void addAdditionalContact() {
    setState(() => additionalContacts.add(ContactFields()));
  }

  void removeAdditionalContact(int index) {
    setState(() {
      additionalContacts.removeAt(index).dispose();
      // Later rows shift down an index; the form rebuilds every contact_ key.
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
