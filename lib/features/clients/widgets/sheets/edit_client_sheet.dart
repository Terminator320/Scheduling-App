import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/errors/error_cause.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/core/validators/text_limits.dart';
import 'package:scheduling/features/clients/application/client_form_controller.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/domain/models/client_type.dart';
import 'package:scheduling/features/clients/domain/policies/client_form_validator.dart';
import 'package:scheduling/features/clients/widgets/client_form_state.dart';
import 'package:scheduling/features/clients/widgets/fields/client_address_section.dart';
import 'package:scheduling/features/clients/widgets/fields/client_type_chips.dart';
import 'package:scheduling/features/clients/widgets/sections/additional_contacts_section.dart';
import 'package:scheduling/features/maps/domain/address_parser.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/cards/sheet_panel.dart';
import 'package:scheduling/shared/widgets/fields/labeled_text_field.dart';
import 'package:scheduling/shared/widgets/fields/sheet_field_row.dart';
import 'package:scheduling/shared/widgets/primitives/mono_section_label.dart';
import 'package:scheduling/shared/widgets/sheets/app_bottom_sheet.dart';
import 'package:scheduling/shared/widgets/sheets/form_sheet_frame.dart';
import 'package:scheduling/shared/widgets/sheets/sheet_widgets.dart';

/// Opens the edit-client sheet. Resolves to the saved record, or null when the
/// sheet was cancelled.
///
/// A nullable record is enough here precisely because clients are never removed
/// (owner decision 2026-08-01) — there is no third "the client is gone" state
/// for null to be confused with.
Future<ClientRecord?> showEditClientSheet(
  BuildContext context,
  ClientRecord client,
) => showAppBottomSheet<ClientRecord>(
  context,
  builder: (_) => EditClientSheet(client: client),
);

class EditClientSheet extends ConsumerStatefulWidget {
  const EditClientSheet({required this.client, super.key});

  final ClientRecord client;

  @override
  ConsumerState<EditClientSheet> createState() => _EditClientSheetState();
}

class _EditClientSheetState extends ConsumerState<EditClientSheet>
    with ClientFormState<EditClientSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _onSiteManagerController;
  late final TextEditingController _accessNotesController;
  late final TextEditingController _billingTermsController;
  late final TextEditingController _addressController;
  late final TextEditingController _aptController;
  late final TextEditingController _cityController;
  late final TextEditingController _provinceController;
  late final TextEditingController _countryController;
  late final TextEditingController _postalCodeController;

  late ClientType _type;
  late bool _autoInvoice;

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
    _emailController = TextEditingController(text: c.email);
    _onSiteManagerController = TextEditingController(text: c.onSiteManager);
    _accessNotesController = TextEditingController(text: c.accessNotes);
    _billingTermsController = TextEditingController(text: c.billingTerms);
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
    // `contacts` is purely the extra contacts (no primary mirror).
    for (final contact in c.contacts) {
      additionalContacts.add(
        ContactFields()
          ..nameController.text = contact.name
          ..phoneController.text = contact.phone
          ..emailController.text = contact.email,
      );
    }
    noFixedAddress = c.noFixedAddress;
    _type = c.type;
    _autoInvoice = c.autoInvoice;
  }

  @override
  void dispose() {
    for (final controller in [
      _nameController,
      _firstNameController,
      _lastNameController,
      _phoneController,
      _emailController,
      _onSiteManagerController,
      _accessNotesController,
      _billingTermsController,
      _addressController,
      _aptController,
      _cityController,
      _provinceController,
      _countryController,
      _postalCodeController,
    ]) {
      controller.dispose();
    }
    disposeAdditionalContacts();
    super.dispose();
  }

  // Prefers the explicit apt field over an apt embedded in the street text.
  String _buildFullAddress() {
    final parsed = AddressParser.splitApt(_addressController.text);
    final street = (parsed?.street ?? _addressController.text).trim();
    final apt = _aptController.text.trim().isNotEmpty
        ? _aptController.text.trim()
        : (parsed?.apt ?? '').trim();
    return AddressParser.combineAptAndStreet(street, apt);
  }

  List<ClientContact> _buildContacts() => [
    for (final contact in additionalContacts)
      if (!contact.isEmpty) contact.toContact(),
  ];

  Future<void> _save() async {
    // Guards against a double-tap firing two concurrent writes.
    if (ref.read(clientFormControllerProvider)) return;

    // Owner decision 2026-08-01. `mobile` is no longer an editable field, so a
    // stored value must not be stranded: promote it when there is no phone, drop
    // it when there is. Runs on every save, so the fleet self-heals as clients
    // are edited — there is no migration script and none is needed.
    final typedPhone = _phoneController.text.trim();
    final storedMobile = widget.client.mobile.trim();
    final resolvedPhone = typedPhone.isNotEmpty ? typedPhone : storedMobile;

    final nextErrors = ClientFormValidator.validate(
      l10n: context.l10n,
      name: _nameController.text.trim(),
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      phone: resolvedPhone,
      mobile: '',
      email: _emailController.text.trim(),
      address: _addressController.text.trim(),
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

    // Copying the loaded record preserves the Wave projection fields
    // (waveCustomerId/waveSyncState/waveSyncError) and the function-owned
    // jobCount — this form never edits any of them.
    final updated = widget.client.copyWith(
      name: _nameController.text.trim(),
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      phone: resolvedPhone,
      mobile: '',
      email: _emailController.text.trim(),
      address: noFixedAddress ? '' : _buildFullAddress(),
      apt: noFixedAddress ? '' : _aptController.text.trim(),
      city: noFixedAddress ? '' : _cityController.text.trim(),
      province: noFixedAddress ? '' : _provinceController.text.trim(),
      country: noFixedAddress ? '' : _countryController.text.trim(),
      postalCode: noFixedAddress ? '' : _postalCodeController.text.trim(),
      contacts: _buildContacts(),
      noFixedAddress: noFixedAddress,
      type: _type,
      accessNotes: _accessNotesController.text.trim(),
      onSiteManager: _onSiteManagerController.text.trim(),
      billingTerms: _billingTermsController.text.trim(),
      autoInvoice: _autoInvoice,
    );

    final outcome = await ref
        .read(clientFormControllerProvider.notifier)
        .updateClient(updated);
    if (!mounted) return;
    switch (outcome) {
      case ClientSaved():
        ref
            .read(noticeServiceProvider)
            .success(context.l10n.common_changesSaved);
        Navigator.pop(context, updated);
      case ClientSaveFailed(:final error):
        ref
            .read(noticeServiceProvider)
            .error(
              composeErrorNotice(
                context,
                intro: context.l10n.error_introSaveClient,
                tag: 'CLI-SAVE',
                error: error,
              ),
            );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final isSaving = ref.watch(clientFormControllerProvider);
    final createdAt = widget.client.createdAt;

    return FormSheetFrame(
      title: l10n.clients_editClient,
      primaryLabel: l10n.common_save,
      isBusy: isSaving,
      onPrimary: _save,
      children: [
        MonoSectionLabel(l10n.clients_sectionClient),
        const SizedBox(height: AppSpacing.sp8),
        SheetFocusScroll(
          child: LabeledTextField(
            label: l10n.clients_nameOrBusiness,
            controller: _nameController,
            required: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            maxLength: TextLimits.personName,
            errorText: errors['name'],
            onChanged: (_) => clearError('name'),
          ),
        ),
        const SizedBox(height: AppSpacing.sp16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SheetFocusScroll(
                child: LabeledTextField(
                  label: l10n.clients_firstName,
                  controller: _firstNameController,
                  optional: true,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  maxLength: TextLimits.firstName,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sp12),
            Expanded(
              child: SheetFocusScroll(
                child: LabeledTextField(
                  label: l10n.clients_lastName,
                  controller: _lastNameController,
                  optional: true,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  maxLength: TextLimits.lastName,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sp12),
        ClientTypeChips(
          value: _type,
          onChanged: (next) => setState(() => _type = next),
        ),
        // Read-only: createdAt is a server timestamp that drives dashboard
        // trends and the clients list order, so it is shown, never edited.
        if (createdAt != null) ...[
          const SizedBox(height: AppSpacing.sp12),
          SheetPanel(
            children: [
              SheetFieldRow(
                label: l10n.clients_since,
                value: DateUtilsHelper.formatDate(createdAt),
                useMonoValue: true,
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.sp24),

        // Owner change 5: one phone, no mobile field. A stored mobile is folded
        // into phone by _save rather than left stranded on the doc.
        MonoSectionLabel(l10n.clients_sectionContact),
        const SizedBox(height: AppSpacing.sp8),
        SheetFocusScroll(
          child: LabeledTextField(
            label: l10n.clients_phone,
            controller: _phoneController,
            optional: true,
            keyboard: TextInputType.phone,
            textInputAction: TextInputAction.next,
            maxLength: TextLimits.phone,
          ),
        ),
        const SizedBox(height: AppSpacing.sp16),
        SheetFocusScroll(
          child: LabeledTextField(
            label: l10n.common_email,
            controller: _emailController,
            optional: true,
            keyboard: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            maxLength: TextLimits.email,
            errorText: errors['email'],
            onChanged: (_) => clearError('email'),
          ),
        ),
        const SizedBox(height: AppSpacing.sp16),
        SheetFocusScroll(
          child: LabeledTextField(
            label: l10n.clients_onSiteManager,
            controller: _onSiteManagerController,
            optional: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            maxLength: TextLimits.clientOnSiteManager,
          ),
        ),
        const SizedBox(height: AppSpacing.sp16),
        AdditionalContactsSection(
          contacts: additionalContacts,
          errors: errors,
          onAddContact: addAdditionalContact,
          onRemoveContact: removeAdditionalContact,
          onClearError: clearError,
        ),
        const SizedBox(height: AppSpacing.sp16),

        MonoSectionLabel(l10n.clients_sectionSite),
        const SizedBox(height: AppSpacing.sp8),
        Material(
          type: MaterialType.transparency,
          child: SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.clients_noFixedAddress),
            subtitle: Text(l10n.clients_noFixedAddressHint),
            value: noFixedAddress,
            activeTrackColor: theme.colorScheme.primary,
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
        const SizedBox(height: AppSpacing.sp16),
        SheetFocusScroll(
          child: LabeledTextField(
            label: l10n.clients_accessNotes,
            hint: l10n.clients_accessNotesHint,
            controller: _accessNotesController,
            optional: true,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            maxLength: TextLimits.clientAccessNotes,
          ),
        ),
        const SizedBox(height: AppSpacing.sp24),

        MonoSectionLabel(l10n.clients_sectionBilling),
        const SizedBox(height: AppSpacing.sp8),
        SheetFocusScroll(
          child: LabeledTextField(
            label: l10n.clients_billingTerms,
            hint: l10n.clients_billingTermsHint,
            controller: _billingTermsController,
            optional: true,
            textCapitalization: TextCapitalization.sentences,
            maxLength: TextLimits.clientBillingTerms,
          ),
        ),
        // Owner change 4: NO Wave customer id row. The link stays server-owned
        // and `copyWith` still carries waveCustomerId / waveSyncState through the
        // save untouched — it is simply not rendered.
        const SizedBox(height: AppSpacing.sp12),
        Material(
          type: MaterialType.transparency,
          child: SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.clients_autoInvoice),
            value: _autoInvoice,
            activeTrackColor: theme.colorScheme.primary,
            onChanged: (value) => setState(() => _autoInvoice = value),
          ),
        ),
      ],
    );
  }
}
