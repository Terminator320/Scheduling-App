import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/animations/animated_loading_button.dart';
import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/validators/text_limits.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/domain/policies/client_form_validator.dart';
import 'package:scheduling/features/clients/widgets/fields/address_grid_fields.dart';
import 'package:scheduling/features/clients/widgets/sections/additional_contacts_section.dart';
import 'package:scheduling/features/maps/address_field_filler.dart';
import 'package:scheduling/features/maps/domain/address_parser.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/fields/address_autocomplete_field.dart';
import 'package:scheduling/shared/widgets/fields/labeled_text_field.dart';
import 'package:scheduling/shared/widgets/sheets/sheet_widgets.dart';

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
      _additionalContacts.removeAt(index).dispose();
      _errors
        ..remove('contact_${index}_name')
        ..remove('contact_${index}_phone')
        ..remove('contact_${index}_email');
    });
  }

  List<ClientContact> _buildContacts() {
    if (!_isBusiness) return const [];
    return [
      ClientContact(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim(),
      ),
      for (final contact in _additionalContacts)
        if (!contact.isEmpty) contact.toContact(),
    ];
  }

  void _handleAddressSelected() {
    Future<void>.microtask(() {
      if (!mounted) return;
      setState(() {
        _errors['address'] = null;
        fillAddressControllersFromText(
          _addressController.text,
          address: _addressController,
          apt: _aptController,
          city: _cityController,
          province: _provinceController,
          postalCode: _postalCodeController,
          country: _countryController,
        );
      });
    });
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
        for (final contact in _additionalContacts) contact.toContact(),
      ],
    );

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
    final theme = Theme.of(context);

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
              context.l10n.clients_newClient,
              style: theme.textTheme.headlineLarge,
            ),
            const SizedBox(height: 20),
            const Divider(height: 1),
            const SizedBox(height: 20),
            SheetFocusScroll(
              child: LabeledTextField(
                label: context.l10n.clients_businessName,
                controller: _businessNameController,
                optional: true,
                autofillHints: const [AutofillHints.organizationName],
                maxLength: TextLimits.personName,
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
                label: context.l10n.clients_contactName,
                controller: _nameController,
                required: !_isBusiness,
                optional: _isBusiness,
                autofillHints: const [AutofillHints.name],
                maxLength: TextLimits.personName,
                errorText: _errors['name'],
                onChanged: (_) {
                  _clearError('name');
                  _clearError('businessName');
                  setState(() {});
                },
              ),
            ),
            const SizedBox(height: 16),
            SheetFocusScroll(
              child: LabeledTextField(
                label: context.l10n.common_email,
                controller: _emailController,
                keyboard: TextInputType.emailAddress,
                optional: true,
                autofillHints: const [AutofillHints.email],
                maxLength: TextLimits.email,
                errorText: _errors['email'],
                onChanged: (_) {
                  _clearError('email');
                  _clearError('phone');
                },
              ),
            ),

            const SizedBox(height: 16),
            SheetFocusScroll(
              child: LabeledTextField(
                label: context.l10n.clients_phone,
                controller: _phoneController,
                keyboard: TextInputType.phone,
                required: true,
                autofillHints: const [AutofillHints.telephoneNumber],
                maxLength: TextLimits.phone,
                errorText: _errors['phone'],
                onChanged: (_) {
                  _clearError('phone');
                  _clearError('email');
                },
              ),
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
                onChanged: (_) => _clearError('address'),
                onAddressSelected: (_) => _handleAddressSelected(),
              ),
            ),
            const SizedBox(height: 16),
            SheetFocusScroll(
              child: LabeledTextField(
                label: context.l10n.clients_aptUnit,
                controller: _aptController,
                optional: true,
                maxLength: TextLimits.aptUnit,
              ),
            ),
            const SizedBox(height: 16),
            AddressGridFields(
              cityController: _cityController,
              provinceController: _provinceController,
              postalCodeController: _postalCodeController,
              countryController: _countryController,
            ),
            const SizedBox(height: 24),
            _AddClientActions(
              isSaving: _isSaving,
              onCancel: _isSaving ? null : () => Navigator.pop(context),
              onSave: _isSaving ? null : _save,
            ),
          ],
        );
      },
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
