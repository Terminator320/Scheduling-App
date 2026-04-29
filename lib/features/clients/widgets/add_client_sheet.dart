import 'package:flutter/material.dart';

import 'package:scheduling/features/clients/models/client_record.dart';
import 'package:scheduling/features/clients/services/client_service.dart';
import 'package:scheduling/shared/widgets/address_autocomplete_field.dart';
import 'package:scheduling/shared/widgets/labeled_text_field.dart';
import 'package:scheduling/shared/widgets/sheet_widgets.dart';

class _ParsedAptAddress {
  final String apt;
  final String street;

  const _ParsedAptAddress({
    required this.apt,
    required this.street,
  });
}


class _ContactFields {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController emailController = TextEditingController();

  bool get isEmpty =>
      nameController.text.trim().isEmpty &&
      phoneController.text.trim().isEmpty &&
      emailController.text.trim().isEmpty;

  ClientContact toContact() {
    return ClientContact(
      name: nameController.text.trim(),
      phone: phoneController.text.trim(),
      email: emailController.text.trim(),
    );
  }

  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();
  }
}

class AddClientSheet extends StatefulWidget {
  const AddClientSheet({super.key});

  @override
  State<AddClientSheet> createState() => _AddClientSheetState();
}

class _AddClientSheetState extends State<AddClientSheet> {
  final _businessNameController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _provinceController = TextEditingController();
  final _countryController = TextEditingController();
  final _postalCodeController = TextEditingController();
  final _aptController = TextEditingController();
  final List<_ContactFields> _additionalContacts = [];

  final _clientService = ClientService();
  final Map<String, String?> _errors = {};
  bool _isSaving = false;

  bool get _isBusiness => _businessNameController.text.trim().isNotEmpty;

  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _businessNameController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _provinceController.dispose();
    _countryController.dispose();
    _postalCodeController.dispose();
    _aptController.dispose();
    for (final contact in _additionalContacts) {
      contact.dispose();
    }
    super.dispose();
  }

  String? _validateEmail(String value) {
    if (value.isEmpty) return null;
    if (!_emailRegex.hasMatch(value)) return "Enter a valid email";
    return null;
  }

  void _clearError(String key) {
    if (_errors[key] != null) setState(() => _errors[key] = null);
  }

  void _addAdditionalContact() {
    setState(() {
      _additionalContacts.add(_ContactFields());
    });
  }

  void _removeAdditionalContact(int index) {
    setState(() {
      final removed = _additionalContacts.removeAt(index);
      removed.dispose();
      _errors.remove('contact_${index}_name');
      _errors.remove('contact_${index}_phone');
      _errors.remove('contact_${index}_email');
    });
  }

  List<ClientContact> _buildContacts() {
    final contacts = <ClientContact>[];

    if (_isBusiness) {
      contacts.add(
        ClientContact(
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim(),
          email: _emailController.text.trim(),
        ),
      );

      for (final contact in _additionalContacts) {
        if (!contact.isEmpty) {
          contacts.add(contact.toContact());
        }
      }
    }

    return contacts;
  }

  _ParsedAptAddress? _splitAptFromAddress(String rawAddress) {
    final value = rawAddress.trim();
    if (value.isEmpty) return null;


    final savedMatch = RegExp(
      r'^Apt-?\s*([^\-]+)\s*-\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(value);

    if (savedMatch != null) {
      return _ParsedAptAddress(
        apt: savedMatch.group(1)!.trim(),
        street: savedMatch.group(2)!.trim(),
      );
    }

    final labeledMatch = RegExp(
      r'^\s*(?:apt|apartment|unit|suite|ste|#)\s*[-#: ]*\s*([A-Za-z0-9][A-Za-z0-9 /]*)\s*[-,]\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(value);

    if (labeledMatch != null) {
      return _ParsedAptAddress(
        apt: labeledMatch.group(1)!.trim(),
        street: labeledMatch.group(2)!.trim(),
      );
    }

    final dashMatch = RegExp(
      r'^\s*([A-Za-z0-9][A-Za-z0-9 /]*)\s*-\s*(\d+.+)$',
    ).firstMatch(value);

    if (dashMatch != null) {
      return _ParsedAptAddress(
        apt: dashMatch.group(1)!.trim(),
        street: dashMatch.group(2)!.trim(),
      );
    }

    // Handles addresses where the unit is written after the street,
    // for example: "1245 Rue de Bleury #3406, Montréal, QC"
    // or: "1245 Rue de Bleury Apt 3406, Montréal, QC".
    final trailingUnitMatch = RegExp(
      r"^\s*(.+?)\s+(?:#|apt\.?|apartment|unit|suite|ste\.?)\s*[-#: ]*\s*([A-Za-z0-9][A-Za-z0-9 /]*)\s*(,.*)?$",
      caseSensitive: false,
    ).firstMatch(value);

    if (trailingUnitMatch != null) {
      final beforeUnit = trailingUnitMatch.group(1)!.trim();
      final apt = trailingUnitMatch.group(2)!.trim();
      final afterUnit = trailingUnitMatch.group(3)?.trim() ?? "";
      return _ParsedAptAddress(
        apt: apt,
        street: afterUnit.isEmpty ? beforeUnit : "$beforeUnit$afterUnit",
      );
    }

    return null;
  }

  String _addressWithVisualApt(String street, String apt) {
    var cleanStreet = street.trim();

    // 🔥 REMOVE any existing unit (#, Apt, Unit, etc.)
    cleanStreet = cleanStreet.replaceAll(
      RegExp(r'\s+(#|apt\.?|apartment|unit|suite|ste\.?)\s*[-#: ]*\s*[A-Za-z0-9 /]+', caseSensitive: false),
      '',
    ).trim();

    final cleanApt = apt.trim().replaceAll(RegExp(r'^#+'), '');
    if (cleanStreet.isEmpty || cleanApt.isEmpty) return cleanStreet;

    final commaIndex = cleanStreet.indexOf(',');

    // 👇 If no city part yet
    if (commaIndex == -1) {
      return '$cleanStreet #$cleanApt';
    }

    // 👇 Insert before city
    final firstLine = cleanStreet.substring(0, commaIndex).trim();
    final rest = cleanStreet.substring(commaIndex);

    return '$firstLine #$cleanApt$rest';
  }

  void _fillAddressPartsFromText(String rawAddress) {
    final aptAddress = _splitAptFromAddress(rawAddress);

    if (aptAddress != null) {
      if (_aptController.text.trim().isEmpty) {
        _aptController.text = aptAddress.apt;
      }

      if (_addressController.text.trim() != aptAddress.street) {
        _addressController.value = TextEditingValue(
          text: aptAddress.street,
          selection: TextSelection.collapsed(offset: aptAddress.street.length),
        );
      }
    }

    final value = (aptAddress?.street ?? rawAddress).trim();
    if (value.isEmpty) return;

    final parts = value
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();

    final postalMatch = RegExp(
      r'\b[ABCEGHJ-NPRSTVXY]\d[ABCEGHJ-NPRSTV-Z][ -]?\d[ABCEGHJ-NPRSTV-Z]\d\b',
      caseSensitive: false,
    ).firstMatch(value);

    if (postalMatch != null) {
      _postalCodeController.text = postalMatch.group(0)!.toUpperCase();
    }

    if (parts.isNotEmpty) {
      final last = parts.last;
      final postal = postalMatch?.group(0);
      if (postal != null && last.toLowerCase().contains(postal.toLowerCase())) {
        if (_countryController.text.trim().isEmpty) {
          _countryController.text = 'Canada';
        }
      } else if (last.length > 2) {
        _countryController.text = last;
      }
    }

    for (final part in parts) {
      final provinceMatch = RegExp(
        r'\b(AB|BC|MB|NB|NL|NS|NT|NU|ON|PE|QC|SK|YT)\b',
        caseSensitive: false,
      ).firstMatch(part);
      if (provinceMatch != null) {
        _provinceController.text = provinceMatch.group(0)!.toUpperCase();
        break;
      }
    }

    if (parts.length >= 3) {
      final possibleCity = parts[parts.length - 3];
      if (!RegExp(r'\d').hasMatch(possibleCity)) {
        _cityController.text = possibleCity;
      }
    } else if (parts.length >= 2) {
      final possibleCity = parts[parts.length - 2];
      if (!RegExp(r'\d').hasMatch(possibleCity)) {
        _cityController.text = possibleCity;
      }
    }
  }

  void _handleAddressSelected() {
    Future<void>.microtask(() {
      if (!mounted) return;
      setState(() {
        _errors['address'] = null;
        _fillAddressPartsFromText(_addressController.text);
      });
    });
  }

  Future<void> _save() async {
    final businessName = _businessNameController.text.trim();
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();
    final address = _addressController.text.trim();
    final hasContactMethod = phone.isNotEmpty || email.isNotEmpty;

    final nextErrors = <String, String?>{};

    final hasBusinessOrName = businessName.isNotEmpty || name.isNotEmpty;

    nextErrors['businessName'] = !hasBusinessOrName
        ? 'Business name or contact name is required'
        : null;
    nextErrors['name'] = !hasBusinessOrName
        ? 'Business name or contact name is required'
        : null;
    nextErrors['phone'] = !hasContactMethod ? 'Phone or email is required' : null;
    nextErrors['email'] = _validateEmail(email);
    nextErrors['address'] = businessName.isEmpty && address.isEmpty
        ? 'Address is required'
        : null;

    if (businessName.isNotEmpty) {
      for (var i = 0; i < _additionalContacts.length; i++) {
        final contact = _additionalContacts[i];
        if (contact.isEmpty) continue;

        final contactName = contact.nameController.text.trim();
        final contactPhone = contact.phoneController.text.trim();
        final contactEmail = contact.emailController.text.trim();
        final hasAdditionalContactMethod =
            contactPhone.isNotEmpty || contactEmail.isNotEmpty;

        nextErrors['contact_${i}_name'] =
            contactName.isEmpty ? 'Contact name is required' : null;
        nextErrors['contact_${i}_phone'] = !hasAdditionalContactMethod
            ? 'Phone or email is required'
            : null;
        nextErrors['contact_${i}_email'] = _validateEmail(contactEmail);
      }
    }

    setState(() {
      _errors
        ..clear()
        ..addAll(nextErrors);
    });

    if (_errors.values.any((e) => e != null)) return;

    setState(() => _isSaving = true);

    final parsedAddress = _splitAptFromAddress(_addressController.text);
    final street = (parsedAddress?.street ?? _addressController.text).trim();
    final apt = _aptController.text.trim().isNotEmpty
        ? _aptController.text.trim()
        : (parsedAddress?.apt ?? '').trim();
    final fullAddress = _addressWithVisualApt(street, apt);

    final newClient = ClientRecord(
      id: '',
      businessName: businessName,
      name: name,
      phone: phone,
      email: email,
      address: fullAddress,
      apt: apt,
      city: _cityController.text.trim(),
      province: _provinceController.text.trim(),
      country: _countryController.text.trim(),
      postalCode: _postalCodeController.text.trim(),
      contacts: _buildContacts(),
    );

    try {
      await _clientService.addClient(newClient);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not add client. Try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SheetHandle(),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  "New client",
                  style: theme.textTheme.headlineLarge,
                ),
              ),
              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 20),
              LabeledTextField(
                label: "Business name",
                controller: _businessNameController,
                optional: true,
                autofillHints: const [AutofillHints.organizationName],
                errorText: _errors['businessName'],
                onChanged: (_) {
                  _clearError('businessName');
                  _clearError('name');
                  _clearError('address');
                  setState(() {});
                },
              ),
              const SizedBox(height: 16),
              LabeledTextField(
                label: "Contact name",
                controller: _nameController,
                required: !_isBusiness,
                optional: _isBusiness,
                autofillHints: const [AutofillHints.name],
                errorText: _errors['name'],
                onChanged: (_) {
                  _clearError('name');
                  _clearError('businessName');
                  setState(() {});
                },
              ),
              const SizedBox(height: 16),
              LabeledTextField(
                label: "Phone",
                controller: _phoneController,
                keyboard: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                errorText: _errors['phone'],
                onChanged: (_) {
                  _clearError('phone');
                  _clearError('email');
                },
              ),
              const SizedBox(height: 16),
              LabeledTextField(
                label: "Email",
                controller: _emailController,
                keyboard: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                errorText: _errors['email'],
                onChanged: (_) {
                  _clearError('email');
                  _clearError('phone');
                },
              ),
              if (_isBusiness) ...[
                const SizedBox(height: 8),
                _AdditionalContactsSection(
                  contacts: _additionalContacts,
                  errors: _errors,
                  onAddContact: _addAdditionalContact,
                  onRemoveContact: _removeAdditionalContact,
                  onClearError: _clearError,
                ),
              ],
              const SizedBox(height: 16),
              AddressAutocompleteField(
                controller: _addressController,
                required: !_isBusiness,
                errorText: _errors['address'],
                onChanged: (value) {
                  _clearError('address');
                  _fillAddressPartsFromText(value);
                },
                onAddressSelected: (_) => _handleAddressSelected(),
              ),
              const SizedBox(height: 16),
              LabeledTextField(
                label: "Apt / Unit",
                controller: _aptController,
                optional: true,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: LabeledTextField(
                      label: "City",
                      controller: _cityController,
                      autofillHints: const [AutofillHints.addressCity],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LabeledTextField(
                      label: "Province",
                      controller: _provinceController,
                      autofillHints: const [AutofillHints.addressState],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: LabeledTextField(
                      label: "Postal code",
                      controller: _postalCodeController,
                      autofillHints: const [AutofillHints.postalCode],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LabeledTextField(
                      label: "Country",
                      controller: _countryController,
                      autofillHints: const [AutofillHints.countryName],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.pop(context),
                      child: const Text("Cancel"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _isSaving ? null : _save,
                      child: _isSaving
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: scheme.onPrimary,
                              ),
                            )
                          : const Text("Add client"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _AdditionalContactsSection extends StatelessWidget {
  final List<_ContactFields> contacts;
  final Map<String, String?> errors;
  final VoidCallback onAddContact;
  final ValueChanged<int> onRemoveContact;
  final ValueChanged<String> onClearError;

  const _AdditionalContactsSection({
    required this.contacts,
    required this.errors,
    required this.onAddContact,
    required this.onRemoveContact,
    required this.onClearError,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Additional business contacts',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onAddContact,
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'The first contact is the main contact above. Add more contacts here if needed.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (contacts.isEmpty) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onAddContact,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add another contact'),
            ),
          ],
          for (var i = 0; i < contacts.length; i++) ...[
            const SizedBox(height: 16),
            _AdditionalContactCard(
              index: i,
              contact: contacts[i],
              errors: errors,
              onRemove: () => onRemoveContact(i),
              onClearError: onClearError,
            ),
          ],
        ],
      ),
    );
  }
}

class _AdditionalContactCard extends StatelessWidget {
  final int index;
  final _ContactFields contact;
  final Map<String, String?> errors;
  final VoidCallback onRemove;
  final ValueChanged<String> onClearError;

  const _AdditionalContactCard({
    required this.index,
    required this.contact,
    required this.errors,
    required this.onRemove,
    required this.onClearError,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Contact ${index + 2}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Remove contact',
                onPressed: onRemove,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LabeledTextField(
            label: 'Contact name',
            controller: contact.nameController,
            required: true,
            autofillHints: const [AutofillHints.name],
            errorText: errors['contact_${index}_name'],
            onChanged: (_) => onClearError('contact_${index}_name'),
          ),
          const SizedBox(height: 12),
          LabeledTextField(
            label: 'Phone',
            controller: contact.phoneController,
            keyboard: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            errorText: errors['contact_${index}_phone'],
            onChanged: (_) => onClearError('contact_${index}_phone'),
          ),
          const SizedBox(height: 12),
          LabeledTextField(
            label: 'Email',
            controller: contact.emailController,
            keyboard: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            errorText: errors['contact_${index}_email'],
            onChanged: (_) {
              onClearError('contact_${index}_email');
              onClearError('contact_${index}_phone');
            },
          ),
        ],
      ),
    );
  }
}
