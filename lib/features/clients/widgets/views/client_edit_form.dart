import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/button_styles.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/contact_export_launcher.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/domain/policies/client_form_validator.dart';
import 'package:scheduling/features/clients/widgets/client_form_state.dart';
import 'package:scheduling/features/clients/widgets/fields/client_address_section.dart';
import 'package:scheduling/features/clients/widgets/sections/additional_contacts_section.dart';
import 'package:scheduling/features/clients/widgets/sections/client_personal_fields_section.dart';
import 'package:scheduling/features/maps/domain/address_parser.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/primitives/entity_form_header.dart';

/// Editable form for a [ClientRecord]. Owns every text controller and the
/// validate/persist flow; it is built only while the detail view is in edit
/// mode, so a plain view never pays for these controllers. On a successful
/// save it reports the updated record via [onSaved]; delete is delegated to
/// the parent through [onDelete] (it is shared with view mode).
class ClientEditForm extends ConsumerStatefulWidget {
  const ClientEditForm({
    required this.client,
    required this.isDeleting,
    required this.onDelete,
    required this.onSaved,
    super.key,
  });

  final ClientRecord client;
  final bool isDeleting;
  final VoidCallback? onDelete;
  final ValueChanged<ClientRecord> onSaved;

  @override
  ConsumerState<ClientEditForm> createState() => _ClientEditFormState();
}

class _ClientEditFormState extends ConsumerState<ClientEditForm>
    with ClientFormState<ClientEditForm> {
  late final TextEditingController _nameController;
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _mobileController;
  late final TextEditingController _emailController;
  late final TextEditingController _addressController;
  late final TextEditingController _aptController;
  late final TextEditingController _cityController;
  late final TextEditingController _provinceController;
  late final TextEditingController _countryController;
  late final TextEditingController _postalCodeController;

  // Guards against a double-tap firing two concurrent writes (mirrors
  // AddClientSheet) — the Save button disables while this is true.
  bool _isSaving = false;

  // Prefers the explicit apt field over an apt embedded in the street text.
  String _buildFullAddress() {
    final parsed = AddressParser.splitApt(_addressController.text);
    final street = (parsed?.street ?? _addressController.text).trim();
    final apt = _aptController.text.trim().isNotEmpty
        ? _aptController.text.trim()
        : (parsed?.apt ?? '').trim();
    return AddressParser.combineAptAndStreet(street, apt);
  }

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  void _initControllers() {
    final c = widget.client;
    _nameController = TextEditingController(text: c.name);
    _firstNameController = TextEditingController(text: c.firstName);
    _lastNameController = TextEditingController(text: c.lastName);
    _phoneController = TextEditingController(text: c.phone);
    _mobileController = TextEditingController(text: c.mobile);
    _emailController = TextEditingController(text: c.email);
    final parsed = AddressParser.splitApt(c.address);
    _addressController = TextEditingController(
      text: parsed?.street ?? c.address,
    );
    _aptController = TextEditingController(
      text: c.apt.isNotEmpty ? c.apt : (parsed?.apt ?? ''),
    );
    _cityController = TextEditingController(text: c.city);
    _provinceController = TextEditingController(text: c.province);
    _countryController = TextEditingController(text: c.country);
    _postalCodeController = TextEditingController(text: c.postalCode);
    // `contacts` is now purely the extra contacts (no primary mirror).
    for (final contact in c.contacts) {
      additionalContacts.add(
        ContactFields()
          ..nameController.text = contact.name
          ..phoneController.text = contact.phone
          ..emailController.text = contact.email,
      );
    }
    noFixedAddress = c.noFixedAddress;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _mobileController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _aptController.dispose();
    _cityController.dispose();
    _provinceController.dispose();
    _countryController.dispose();
    _postalCodeController.dispose();
    disposeAdditionalContacts();
    super.dispose();
  }

  List<ClientContact> _buildContacts() => [
    for (final contact in additionalContacts)
      if (!contact.isEmpty) contact.toContact(),
  ];

  Future<void> _save() async {
    if (_isSaving) return;
    final name = _nameController.text.trim();
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final phone = _phoneController.text.trim();
    final mobile = _mobileController.text.trim();
    final email = _emailController.text.trim();
    final address = _addressController.text.trim();

    final nextErrors = ClientFormValidator.validate(
      l10n: context.l10n,
      name: name,
      firstName: firstName,
      lastName: lastName,
      phone: phone,
      mobile: mobile,
      email: email,
      address: address,
      additionalContacts: [
        for (final contact in additionalContacts) contact.toContact(),
      ],
      noFixedAddress: noFixedAddress,
    );

    setState(() {
      errors
        ..clear()
        ..addAll(nextErrors);
    });

    if (errors.values.any((e) => e != null)) return;

    setState(() => _isSaving = true);

    // --- Build & persist ---
    // Preserves the Wave projection fields (waveCustomerId / waveSyncState /
    // waveSyncError) by copying the loaded record — they're never edited here
    // and toMap drops them anyway.
    final updated = widget.client.copyWith(
      name: name,
      firstName: firstName,
      lastName: lastName,
      phone: phone,
      mobile: mobile,
      email: email,
      address: noFixedAddress ? '' : _buildFullAddress(),
      apt: noFixedAddress ? '' : _aptController.text.trim(),
      city: noFixedAddress ? '' : _cityController.text.trim(),
      province: noFixedAddress ? '' : _provinceController.text.trim(),
      country: noFixedAddress ? '' : _countryController.text.trim(),
      postalCode: noFixedAddress ? '' : _postalCodeController.text.trim(),
      contacts: _buildContacts(),
      noFixedAddress: noFixedAddress,
    );

    try {
      await ref.read(clientsRepositoryProvider).updateClient(updated);
      ref.read(clientsRefreshProvider.notifier).bump();
      // Mirror the edit onto the phone contact this client was saved as (no-op
      // unless it was saved on this device). Best-effort — never blocks save.
      await updateLinkedPhoneContact(ref, updated);
      if (!mounted) return;
      ref.read(noticeServiceProvider).success(context.l10n.common_changesSaved);
      widget.onSaved(updated);
    } catch (e, st) {
      ref.read(loggerProvider).warn('CLI-SAVE updateClient failed', e, st);
      if (!mounted) return;
      ref
          .read(noticeServiceProvider)
          .error(
            composeErrorNotice(
              context,
              intro: context.l10n.error_introSaveClient,
              tag: 'CLI-SAVE',
              error: e,
            ),
          );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // --- Header ---
        EntityFormHeader(name: widget.client.displayName),
        const SizedBox(height: AppSpacing.sp16),
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.sp16),

        // --- Names, phone, mobile & email ---
        ClientPersonalFieldsSection(
          nameController: _nameController,
          firstNameController: _firstNameController,
          lastNameController: _lastNameController,
          phoneController: _phoneController,
          mobileController: _mobileController,
          emailController: _emailController,
          nameError: errors['name'],
          emailError: errors['email'],
          onClearError: clearError,
        ),

        // --- Additional contacts ---
        const SizedBox(height: AppSpacing.sp8),
        AdditionalContactsSection(
          contacts: additionalContacts,
          errors: errors,
          onAddContact: addAdditionalContact,
          onRemoveContact: removeAdditionalContact,
          onClearError: clearError,
        ),
        const SizedBox(height: AppSpacing.sp8),
        // --- Address ---
        Material(
          type: MaterialType.transparency,
          child: SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(context.l10n.clients_noFixedAddress),
            subtitle: Text(context.l10n.clients_noFixedAddressHint),
            value: noFixedAddress,
            activeTrackColor: Theme.of(context).colorScheme.primary,
            onChanged: (value) => setNoFixedAddress(value: value),
          ),
        ),
        if (!noFixedAddress) ...[
          const SizedBox(height: AppSpacing.sp16),
          ClientAddressSection(
            addressController: _addressController,
            aptController: _aptController,
            cityController: _cityController,
            provinceController: _provinceController,
            postalCodeController: _postalCodeController,
            countryController: _countryController,
            isRequired: true,
            errorText: errors['address'],
            onAddressErrorCleared: () => clearError('address'),
          ),
        ],
        const SizedBox(height: AppSpacing.sp24),
        _EditActions(
          onSave: _save,
          onDelete: widget.onDelete,
          isSaving: _isSaving,
        ),
      ],
    );
  }
}

class _EditActions extends StatelessWidget {
  const _EditActions({
    required this.onSave,
    required this.onDelete,
    required this.isSaving,
  });

  final VoidCallback onSave;
  final VoidCallback? onDelete;
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 46),
          ),
          onPressed: isSaving ? null : onSave,
          child: Text(context.l10n.common_saveChanges),
        ),
        const SizedBox(height: AppSpacing.sp8),
        OutlinedButton(
          style: destructiveOutlinedButtonStyle(
            context,
            minimumSize: const Size(double.infinity, 44),
          ),
          onPressed: onDelete,
          child: Text(context.l10n.common_delete),
        ),
      ],
    );
  }
}
