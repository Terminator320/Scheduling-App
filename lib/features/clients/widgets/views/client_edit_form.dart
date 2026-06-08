import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/button_styles.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/validators/text_limits.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/domain/policies/client_form_validator.dart';
import 'package:scheduling/features/clients/widgets/client_form_state.dart';
import 'package:scheduling/features/clients/widgets/fields/client_address_section.dart';
import 'package:scheduling/features/clients/widgets/sections/additional_contacts_section.dart';
import 'package:scheduling/features/maps/domain/address_parser.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/fields/labeled_text_field.dart';
import 'package:scheduling/shared/widgets/primitives/entity_form_header.dart';
import 'package:scheduling/shared/widgets/sheets/sheet_widgets.dart';

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
  late final TextEditingController _businessNameController;
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _addressController;
  late final TextEditingController _aptController;
  late final TextEditingController _cityController;
  late final TextEditingController _provinceController;
  late final TextEditingController _countryController;
  late final TextEditingController _postalCodeController;

  // A business name marks the client as a business and unlocks extra contacts.
  bool get _isBusiness => _businessNameController.text.trim().isNotEmpty;

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
    _businessNameController = TextEditingController(text: c.businessName);
    _nameController = TextEditingController(text: c.name);
    _phoneController = TextEditingController(text: c.phone);
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
    // contacts[0] mirrors the main name/phone/email fields; the rest are
    // the additional business contacts.
    for (final contact in c.contacts.skip(1)) {
      additionalContacts.add(
        ContactFields()
          ..nameController.text = contact.name
          ..phoneController.text = contact.phone
          ..emailController.text = contact.email,
      );
    }
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
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

  List<ClientContact> _buildContacts() {
    // Clearing the business name hides the section but preserves the
    // previously saved contacts.
    if (!_isBusiness) return widget.client.contacts;

    return [
      ClientContact(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim(),
      ),
      for (final contact in additionalContacts)
        if (!contact.isEmpty) contact.toContact(),
    ];
  }

  Future<void> _save() async {
    final businessName = _businessNameController.text.trim();
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();
    final address = _addressController.text.trim();

    final nextErrors = ClientFormValidator.validate(
      l10n: context.l10n,
      businessName: businessName,
      name: name,
      phone: phone,
      email: email,
      address: address,
      additionalContacts: [
        for (final contact in additionalContacts) contact.toContact(),
      ],
    );

    setState(() {
      errors
        ..clear()
        ..addAll(nextErrors);
    });

    if (errors.values.any((e) => e != null)) return;

    // --- Build & persist ---
    final updated = ClientRecord(
      id: widget.client.id,
      businessName: businessName,
      name: name,
      phone: phone,
      email: email,
      address: _buildFullAddress(),
      apt: _aptController.text.trim(),
      city: _cityController.text.trim(),
      province: _provinceController.text.trim(),
      country: _countryController.text.trim(),
      postalCode: _postalCodeController.text.trim(),
      contacts: _buildContacts(),
    );

    try {
      await ref.read(clientsRepositoryProvider).updateClient(updated);
      ref.read(clientsRefreshProvider.notifier).bump();
      if (!mounted) return;
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
        const SizedBox(height: 14),

        // --- Business & contact name ---
        SheetFocusScroll(
          child: LabeledTextField(
            label: context.l10n.clients_businessName,
            controller: _businessNameController,
            optional: true,
            autofillHints: const [AutofillHints.organizationName],
            maxLength: TextLimits.personName,
            errorText: errors['businessName'],
            onChanged: (_) {
              clearError('businessName');
              clearError('name');
              clearError('address');
              setState(() {});
            },
          ),
        ),
        const SizedBox(height: AppSpacing.sp16),
        SheetFocusScroll(
          child: LabeledTextField(
            label: context.l10n.clients_contactName,
            controller: _nameController,
            required: _businessNameController.text.trim().isEmpty,
            optional: _businessNameController.text.trim().isNotEmpty,
            autofillHints: const [AutofillHints.name],
            maxLength: TextLimits.personName,
            errorText: errors['name'],
            onChanged: (_) {
              clearError('name');
              clearError('businessName');
              setState(() {});
            },
          ),
        ),
        const SizedBox(height: AppSpacing.sp16),
        // --- Phone & email ---
        SheetFocusScroll(
          child: LabeledTextField(
            label: context.l10n.clients_phone,
            controller: _phoneController,
            keyboard: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            maxLength: TextLimits.phone,
            errorText: errors['phone'],
            onChanged: (_) {
              clearError('phone');
              clearError('email');
            },
          ),
        ),
        const SizedBox(height: AppSpacing.sp16),
        SheetFocusScroll(
          child: LabeledTextField(
            label: context.l10n.common_email,
            controller: _emailController,
            keyboard: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            maxLength: TextLimits.email,
            errorText: errors['email'],
            onChanged: (_) {
              clearError('email');
              clearError('phone');
            },
          ),
        ),

        // --- Additional business contacts ---
        if (_isBusiness) ...[
          const SizedBox(height: AppSpacing.sp8),
          AdditionalContactsSection(
            contacts: additionalContacts,
            errors: errors,
            onAddContact: addAdditionalContact,
            onRemoveContact: removeAdditionalContact,
            onClearError: clearError,
          ),
        ],
        const SizedBox(height: AppSpacing.sp16),
        // --- Address ---
        ClientAddressSection(
          addressController: _addressController,
          aptController: _aptController,
          cityController: _cityController,
          provinceController: _provinceController,
          postalCodeController: _postalCodeController,
          countryController: _countryController,
          isRequired: _businessNameController.text.trim().isEmpty,
          errorText: errors['address'],
          onAddressErrorCleared: () => clearError('address'),
        ),
        const SizedBox(height: AppSpacing.sp24),
        _EditActions(onSave: _save, onDelete: widget.onDelete),
      ],
    );
  }
}

class _EditActions extends StatelessWidget {
  const _EditActions({required this.onSave, required this.onDelete});

  final VoidCallback onSave;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 46),
          ),
          onPressed: onSave,
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
