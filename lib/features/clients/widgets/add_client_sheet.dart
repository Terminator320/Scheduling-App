import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/core/validators/auth_validators.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/widgets/additional_contacts_section.dart';
import 'package:scheduling/features/maps/domain/address_parser.dart';
import 'package:scheduling/shared/widgets/address_autocomplete_field.dart';
import 'package:scheduling/shared/widgets/labeled_text_field.dart';
import 'package:scheduling/shared/widgets/sheet_widgets.dart';

class AddClientSheet extends ConsumerStatefulWidget {
  const AddClientSheet({super.key});

  @override
  ConsumerState<AddClientSheet> createState() => _AddClientSheetState();
}

class _AddClientSheetState extends ConsumerState<AddClientSheet> {
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
  final List<ContactFields> _additionalContacts = [];

  final Map<String, String?> _errors = {};
  bool _isSaving = false;

  bool get _isBusiness => _businessNameController.text.trim().isNotEmpty;

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
    if (!AuthValidators.isValidEmailFormat(value)) {
      return context.l10n.enterAValidEmail;
    }
    return null;
  }

  void _clearError(String key) {
    if (_errors[key] != null) setState(() => _errors[key] = null);
  }

  void _addAdditionalContact() {
    setState(() {
      _additionalContacts.add(ContactFields());
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

  void _fillAddressPartsFromText(String rawAddress) {
    final fields = AddressParser.parse(rawAddress);

    if (fields.apt != null && _aptController.text.trim().isEmpty) {
      _aptController.text = fields.apt!;
    }
    if (fields.street != null &&
        _addressController.text.trim() != fields.street) {
      _addressController.value = TextEditingValue(
        text: fields.street!,
        selection: TextSelection.collapsed(offset: fields.street!.length),
      );
    }
    if (fields.postalCode != null) {
      _postalCodeController.text = fields.postalCode!;
    }
    if (fields.country != null &&
        (fields.country != 'Canada' || _countryController.text.trim().isEmpty)) {
      _countryController.text = fields.country!;
    }
    if (fields.province != null) _provinceController.text = fields.province!;
    if (fields.city != null) _cityController.text = fields.city!;
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
        ? context.l10n.businessNameOrContactNameIsRequired
        : null;
    nextErrors['name'] = !hasBusinessOrName
        ? context.l10n.businessNameOrContactNameIsRequired
        : null;
    nextErrors['phone'] = !hasContactMethod
        ? context.l10n.phoneOrEmailIsRequired
        : null;
    nextErrors['email'] = _validateEmail(email);
    nextErrors['address'] = businessName.isEmpty && address.isEmpty
        ? context.l10n.addressIsRequired
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
            contactName.isEmpty ? context.l10n.contactNameIsRequired : null;
        nextErrors['contact_${i}_phone'] = !hasAdditionalContactMethod
            ? context.l10n.phoneOrEmailIsRequired
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

    final parsedAddress = AddressParser.splitApt(_addressController.text);
    final street = (parsedAddress?.street ?? _addressController.text).trim();
    final apt = _aptController.text.trim().isNotEmpty
        ? _aptController.text.trim()
        : (parsedAddress?.apt ?? '').trim();
    final fullAddress = AddressParser.combineAptAndStreet(street, apt);

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
      await ref.read(clientsRepositoryProvider).addClient(newClient);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ref
          .read(noticeServiceProvider)
          .error(context.l10n.couldNotAddClientTryAgain);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return DraggableSheetFrame(
      builder: (sheetContext, scrollController) {
        return ListView(
          controller: scrollController,
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
          ),
          children: [
              const SheetHandle(),
              const SizedBox(height: 16),
              Text(
                context.l10n.newClient,
                style: theme.textTheme.headlineLarge,
              ),
              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 20),
              SheetFocusScroll(
                child: LabeledTextField(
                  label: context.l10n.businessName,
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
              ),
              const SizedBox(height: 16),
              SheetFocusScroll(
                child: LabeledTextField(
                  label: context.l10n.contactName,
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
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SheetFocusScroll(
                      child: LabeledTextField(
                        label: context.l10n.phone,
                        controller: _phoneController,
                        keyboard: TextInputType.phone,
                        required: true,
                        autofillHints: const [AutofillHints.telephoneNumber],
                        errorText: _errors['phone'],
                        onChanged: (_) {
                          _clearError('phone');
                          _clearError('email');
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SheetFocusScroll(
                      child: LabeledTextField(
                        label: context.l10n.email,
                        controller: _emailController,
                        keyboard: TextInputType.emailAddress,
                        optional: true,
                        autofillHints: const [AutofillHints.email],
                        errorText: _errors['email'],
                        onChanged: (_) {
                          _clearError('email');
                          _clearError('phone');
                        },
                      ),
                    ),
                  ),
                ],
              ),
              if (_isBusiness) ...[
                const SizedBox(height: 8),
                AdditionalContactsSection(
                  contacts: _additionalContacts,
                  errors: _errors,
                  onAddContact: _addAdditionalContact,
                  onRemoveContact: _removeAdditionalContact,
                  onClearError: _clearError,
                ),
              ],
              const SizedBox(height: 16),
              SheetFocusScroll(
                child: AddressAutocompleteField(
                  controller: _addressController,
                  required: !_isBusiness,
                  errorText: _errors['address'],
                  onChanged: (value) {
                    _clearError('address');
                    _fillAddressPartsFromText(value);
                  },
                  onAddressSelected: (_) => _handleAddressSelected(),
                ),
              ),
              const SizedBox(height: 16),
              SheetFocusScroll(
                child: LabeledTextField(
                  label: context.l10n.aptUnit,
                  controller: _aptController,
                  optional: true,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: SheetFocusScroll(
                      child: LabeledTextField(
                        label: context.l10n.city,
                        controller: _cityController,
                        autofillHints: const [AutofillHints.addressCity],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SheetFocusScroll(
                      child: LabeledTextField(
                        label: context.l10n.province,
                        controller: _provinceController,
                        autofillHints: const [AutofillHints.addressState],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: SheetFocusScroll(
                      child: LabeledTextField(
                        label: context.l10n.postalCode,
                        controller: _postalCodeController,
                        autofillHints: const [AutofillHints.postalCode],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SheetFocusScroll(
                      child: LabeledTextField(
                        label: context.l10n.country,
                        controller: _countryController,
                        autofillHints: const [AutofillHints.countryName],
                      ),
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
                        minimumSize: const Size(double.infinity, 46),
                      ),
                      onPressed: _isSaving ? null : () => Navigator.pop(context),
                      child: Text(context.l10n.cancel),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 46),
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
                          : Text(context.l10n.saveClient),
                    ),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}
