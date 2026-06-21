import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/animations/animated_loading_button.dart';
import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/notices/notice_service.dart';
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
import 'package:scheduling/shared/widgets/sheets/sheet_widgets.dart';

class AddClientSheet extends ConsumerStatefulWidget {
  const AddClientSheet({super.key});

  @override
  ConsumerState<AddClientSheet> createState() => _AddClientSheetState();
}

class _AddClientSheetState extends ConsumerState<AddClientSheet>
    with ClientFormState<AddClientSheet> {
  final _nameController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _mobileController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _provinceController = TextEditingController();
  final _countryController = TextEditingController();
  final _postalCodeController = TextEditingController();
  final _aptController = TextEditingController();

  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _mobileController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _provinceController.dispose();
    _countryController.dispose();
    _postalCodeController.dispose();
    _aptController.dispose();
    disposeAdditionalContacts();
    super.dispose();
  }

  List<ClientContact> _buildContacts() => [
    for (final contact in additionalContacts)
      if (!contact.isEmpty) contact.toContact(),
  ];

  Future<void> _save() async {
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

    final parsedAddress = AddressParser.splitApt(_addressController.text);
    final street = (parsedAddress?.street ?? _addressController.text).trim();
    final apt = _aptController.text.trim().isNotEmpty
        ? _aptController.text.trim()
        : (parsedAddress?.apt ?? '').trim();
    final fullAddress = AddressParser.combineAptAndStreet(street, apt);

    final newClient = ClientRecord(
      id: '',
      name: name,
      firstName: firstName,
      lastName: lastName,
      phone: phone,
      mobile: mobile,
      email: email,
      address: noFixedAddress ? '' : fullAddress,
      apt: noFixedAddress ? '' : apt,
      city: noFixedAddress ? '' : _cityController.text.trim(),
      province: noFixedAddress ? '' : _provinceController.text.trim(),
      country: noFixedAddress ? '' : _countryController.text.trim(),
      postalCode: noFixedAddress ? '' : _postalCodeController.text.trim(),
      contacts: _buildContacts(),
      noFixedAddress: noFixedAddress,
    );

    try {
      await ref.read(clientsRepositoryProvider).addClient(newClient);
      ref.read(clientsRefreshProvider.notifier).bump();
      if (!mounted) return;
      ref.read(noticeServiceProvider).success(context.l10n.common_clientAdded);
      Navigator.pop(context);
    } catch (e, st) {
      ref.read(loggerProvider).warn('CLI-ADD addClient failed', e, st);
      if (!mounted) return;
      setState(() => _isSaving = false);
      ref
          .read(noticeServiceProvider)
          .error(
            composeErrorNotice(
              context,
              intro: context.l10n.error_introAddClient,
              tag: 'CLI-ADD',
              error: e,
            ),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormSheetScaffold(
      title: context.l10n.clients_newClient,
      children: [
        const SizedBox(height: 20),
        const Divider(height: 1),
        const SizedBox(height: 20),
        SheetFocusScroll(
          child: LabeledTextField(
            label: context.l10n.clients_customerName,
            controller: _nameController,
            required: true,
            autofillHints: const [AutofillHints.name],
            maxLength: TextLimits.personName,
            errorText: errors['name'],
            onChanged: (_) => clearError('name'),
          ),
        ),
        const SizedBox(height: AppSpacing.sp16),
        SheetFocusScroll(
          child: LabeledTextField(
            label: context.l10n.clients_firstName,
            controller: _firstNameController,
            optional: true,
            autofillHints: const [AutofillHints.givenName],
            maxLength: TextLimits.firstName,
          ),
        ),
        const SizedBox(height: AppSpacing.sp16),
        SheetFocusScroll(
          child: LabeledTextField(
            label: context.l10n.clients_lastName,
            controller: _lastNameController,
            optional: true,
            autofillHints: const [AutofillHints.familyName],
            maxLength: TextLimits.lastName,
          ),
        ),
        const SizedBox(height: AppSpacing.sp16),
        SheetFocusScroll(
          child: LabeledTextField(
            label: context.l10n.clients_phone,
            controller: _phoneController,
            keyboard: TextInputType.phone,
            optional: true,
            autofillHints: const [AutofillHints.telephoneNumber],
            maxLength: TextLimits.phone,
          ),
        ),
        const SizedBox(height: AppSpacing.sp16),
        SheetFocusScroll(
          child: LabeledTextField(
            label: context.l10n.clients_mobile,
            controller: _mobileController,
            keyboard: TextInputType.phone,
            optional: true,
            autofillHints: const [AutofillHints.telephoneNumber],
            maxLength: TextLimits.mobile,
          ),
        ),
        const SizedBox(height: AppSpacing.sp16),
        SheetFocusScroll(
          child: LabeledTextField(
            label: context.l10n.common_email,
            controller: _emailController,
            keyboard: TextInputType.emailAddress,
            optional: true,
            autofillHints: const [AutofillHints.email],
            maxLength: TextLimits.email,
            errorText: errors['email'],
            onChanged: (_) => clearError('email'),
          ),
        ),
        const SizedBox(height: AppSpacing.sp8),
        AdditionalContactsSection(
          contacts: additionalContacts,
          errors: errors,
          onAddContact: addAdditionalContact,
          onRemoveContact: removeAdditionalContact,
          onClearError: clearError,
        ),
        const SizedBox(height: AppSpacing.sp8),
        Material(
          type: MaterialType.transparency,
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.l10n.clients_noFixedAddress),
            subtitle: Text(context.l10n.clients_noFixedAddressHint),
            value: noFixedAddress,
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
        _AddClientActions(
          isSaving: _isSaving,
          onCancel: _isSaving ? null : () => Navigator.pop(context),
          onSave: _isSaving ? null : _save,
        ),
      ],
    );
  }
}

class _AddClientActions extends StatelessWidget {
  const _AddClientActions({
    required this.isSaving,
    required this.onCancel,
    required this.onSave,
  });

  final bool isSaving;
  final VoidCallback? onCancel;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 46),
            ),
            onPressed: onCancel,
            child: Text(context.l10n.common_cancel),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: AnimatedLoadingButton(
            label: context.l10n.clients_saveClient,
            isLoading: isSaving,
            onPressed: onSave,
            height: 46,
          ),
        ),
      ],
    );
  }
}
