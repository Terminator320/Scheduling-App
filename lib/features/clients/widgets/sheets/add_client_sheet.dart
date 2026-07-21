import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/animations/animated_loading_button.dart';
import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/sheet_focus.dart';
import 'package:scheduling/features/clients/application/client_form_controller.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/domain/policies/client_form_validator.dart';
import 'package:scheduling/features/clients/widgets/client_form_state.dart';
import 'package:scheduling/features/clients/widgets/fields/client_address_section.dart';
import 'package:scheduling/features/clients/widgets/sections/additional_contacts_section.dart';
import 'package:scheduling/features/clients/widgets/sections/client_personal_fields_section.dart';
import 'package:scheduling/features/maps/domain/address_parser.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/sheets/app_bottom_sheet.dart';
import 'package:scheduling/shared/widgets/sheets/sheet_widgets.dart';

/// Opens the add-client sheet and resolves to the newly created client (with
/// its Firestore id populated) once saved, or null if dismissed. [initialName]
/// prefills the name field. Pass [settleFocus] when opening from a search field
/// (the appointment client picker) to settle the keyboard before the sheet
/// slides in and double-unfocus after it closes — the sheet-from-search idiom,
/// mirroring `_openClient` in clients_list_view; FAB openers leave it false.
Future<ClientRecord?> showAddClientSheet(
  BuildContext context, {
  String? initialName,
  bool settleFocus = false,
}) async {
  if (settleFocus) {
    await SheetFocus.settleBeforeSheet();
    if (!context.mounted) return null;
  }
  final created = await showAppBottomSheet<ClientRecord>(
    context,
    builder: (_) => AddClientSheet(initialName: initialName),
  );
  if (settleFocus && context.mounted) await SheetFocus.unfocusAfterSheet();
  // Final guard: if the caller unmounted while the sheet (or unfocus delay) was
  // open, don't hand a client back to a now-disposed form to select.
  return context.mounted ? created : null;
}

class AddClientSheet extends ConsumerStatefulWidget {
  const AddClientSheet({super.key, this.initialName});

  /// Prefills the name field (e.g. the text typed into the appointment client
  /// search before choosing to add a new client).
  final String? initialName;

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

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.initialName ?? '';
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

    final outcome = await ref
        .read(clientFormControllerProvider.notifier)
        .addClient(newClient);
    if (!mounted) return;
    switch (outcome) {
      case ClientSaved(:final client):
        ref
            .read(noticeServiceProvider)
            .success(context.l10n.common_clientAdded);
        Navigator.pop(context, client);
      case ClientSaveFailed(:final error):
        ref
            .read(noticeServiceProvider)
            .error(
              composeErrorNotice(
                context,
                intro: context.l10n.error_introAddClient,
                tag: 'CLI-ADD',
                error: error,
              ),
            );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSaving = ref.watch(clientFormControllerProvider).isSaving;
    return FormSheetScaffold(
      title: context.l10n.clients_newClient,
      children: [
        const SizedBox(height: AppSpacing.sp24),
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.sp24),
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
        _AddClientActions(
          isSaving: isSaving,
          onCancel: isSaving ? null : () => Navigator.pop(context),
          onSave: isSaving ? null : _save,
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
        const SizedBox(width: AppSpacing.sp12),
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
