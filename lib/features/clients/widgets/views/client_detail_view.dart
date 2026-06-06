import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/validators/text_limits.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/domain/policies/client_form_validator.dart';
import 'package:scheduling/features/clients/widgets/fields/address_grid_fields.dart';
import 'package:scheduling/features/clients/widgets/sections/additional_contacts_section.dart';
import 'package:scheduling/features/maps/address_field_filler.dart';
import 'package:scheduling/features/maps/address_map_launcher.dart';
import 'package:scheduling/features/maps/domain/address_parser.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/dialogs/confirm_dialog.dart';
import 'package:scheduling/shared/widgets/fields/address_autocomplete_field.dart';
import 'package:scheduling/shared/widgets/fields/labeled_text_field.dart';
import 'package:scheduling/shared/widgets/primitives/app_avatar.dart';
import 'package:scheduling/shared/widgets/primitives/section_label.dart';
import 'package:scheduling/shared/widgets/sheets/sheet_widgets.dart';

class ClientDetailView extends ConsumerStatefulWidget {
  const ClientDetailView({
    required this.client,
    super.key,
    this.scrollController,
    this.showHandle = false,
    this.bottomPadding = 24,
  });

  final ClientRecord client;
  final ScrollController? scrollController;
  final bool showHandle;
  final double bottomPadding;

  @override
  ConsumerState<ClientDetailView> createState() => _ClientDetailViewState();
}

class _ClientDetailViewState extends ConsumerState<ClientDetailView> {
  bool _isEditing = false;
  bool _isDeleting = false;
  final Map<String, String?> _errors = {};

  late ClientRecord _client;

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
  final List<ContactFields> _additionalContacts = [];

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
    _client = widget.client;
    _initControllers();
  }

  void _initControllers() {
    final c = _client;
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
      _additionalContacts.add(
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
      // Later rows shift down an index; _save rebuilds every contact_ key.
      _errors
        ..remove('contact_${index}_name')
        ..remove('contact_${index}_phone')
        ..remove('contact_${index}_email');
    });
  }

  List<ClientContact> _buildContacts() {
    // Clearing the business name hides the section but preserves the
    // previously saved contacts.
    if (!_isBusiness) return _client.contacts;

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
    // Microtask: let the autocomplete finish writing the controller first.
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

    // --- Build & persist ---
    final updated = ClientRecord(
      id: _client.id,
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
      if (mounted) {
        setState(() {
          _client = updated;
          _isEditing = false;
        });
      }
    } catch (e, st) {
      ref.read(loggerProvider).warn('updateClient failed', e, st);
      if (!mounted) return;
      ref
          .read(noticeServiceProvider)
          .error(context.l10n.error_couldNotSaveChangesTryAgain);
    }
  }

  Future<void> _confirmDelete() async {
    final clientName = _client.displayName.isNotEmpty
        ? _client.displayName
        : context.l10n.clients_thisClient;

    final shouldDelete = await showConfirmDialog(
      context,
      title: context.l10n.clients_deleteClient,
      message:
          '${context.l10n.clients_areYouSureYouWantToDelete} $clientName? ${context.l10n.clients_thisCannotBeUndone}',
      confirmLabel: context.l10n.common_delete,
    );

    if (!shouldDelete || !mounted) return;

    setState(() => _isDeleting = true);

    final notices = ref.read(noticeServiceProvider);
    try {
      await ref.read(clientsRepositoryProvider).deleteClient(_client.id);
      ref.read(clientsRefreshProvider.notifier).bump();
      if (!mounted) return;
      // A scrollController means we're inside a bottom sheet — close it.
      if (widget.scrollController != null) {
        Navigator.pop(context);
      }
      notices.success(context.l10n.clients_clientDeletedSuccessfully);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isDeleting = false);
      notices.error(context.l10n.error_couldNotDeleteClientTryAgain);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return ListView(
      controller: widget.scrollController,
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: bottomInset + widget.bottomPadding,
      ),
      children: [
        if (widget.showHandle) const SheetHandle(),
        if (widget.showHandle) const SizedBox(height: 16),
        if (_isEditing)
          Text(
            context.l10n.clients_editClient,
            style: theme.textTheme.headlineLarge,
          )
        else
          _ViewHeader(client: _client),
        const SizedBox(height: 20),
        const Divider(height: 1),
        const SizedBox(height: 20),
        if (_isEditing) ..._buildEditFields() else ..._buildViewFields(theme),
        const SizedBox(height: 24),
        _DetailActionBar(
          isEditing: _isEditing,
          isDeleting: _isDeleting,
          onSave: _save,
          onDelete: _isDeleting ? null : _confirmDelete,
          onEdit: _isDeleting ? null : () => setState(() => _isEditing = true),
        ),
      ],
    );
  }

  List<Widget> _buildViewFields(ThemeData theme) {
    final c = _client;
    final scheme = theme.colorScheme;
    final hasContactInfo =
        c.phone.isNotEmpty || c.email.isNotEmpty || c.address.isNotEmpty;

    return [
      // --- Contact info card ---
      if (hasContactInfo)
        Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(AppRadius.r12),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.r12),
            child: Column(
              children: [
                if (c.phone.isNotEmpty) ...[
                  _ViewContactRow(icon: Icons.phone_outlined, text: c.phone),
                  if (c.email.isNotEmpty || c.address.isNotEmpty)
                    const Divider(height: 1, indent: 48),
                ],
                if (c.email.isNotEmpty) ...[
                  _ViewContactRow(icon: Icons.email_outlined, text: c.email),
                  if (c.address.isNotEmpty)
                    const Divider(height: 1, indent: 48),
                ],
                if (c.address.isNotEmpty)
                  _ViewContactRow(
                    icon: Icons.location_on_outlined,
                    text: AddressParser.canonicalToDisplay(c.address),
                    onTap: () => AddressMapLauncher.showMapChoices(
                      context,
                      address: c.address,
                    ),
                    color: scheme.primary,
                  ),
              ],
            ),
          ),
        ),
      // --- Business contacts list ---
      if (c.contacts.isNotEmpty) ...[
        const SizedBox(height: 24),
        SectionLabel(context.l10n.common_contacts),
        const SizedBox(height: 8),
        ...c.contacts.map((contact) => _buildContactCard(contact, scheme)),
      ],
    ];
  }

  Widget _buildContactCard(ClientContact contact, ColorScheme scheme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.r12),
        child: Column(
          children: [
            if (contact.name.isNotEmpty) ...[
              _ViewContactRow(icon: Icons.person_outline, text: contact.name),
              if (contact.phone.isNotEmpty || contact.email.isNotEmpty)
                const Divider(height: 1, indent: 48),
            ],
            if (contact.phone.isNotEmpty) ...[
              _ViewContactRow(icon: Icons.phone_outlined, text: contact.phone),
              if (contact.email.isNotEmpty)
                const Divider(height: 1, indent: 48),
            ],
            if (contact.email.isNotEmpty)
              _ViewContactRow(icon: Icons.email_outlined, text: contact.email),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildEditFields() {
    final theme = Theme.of(context);
    return [
      // --- Header ---
      Row(
        children: [
          AppAvatar(name: _client.displayName, size: AvatarSize.lg),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _client.displayName,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
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
          required: _businessNameController.text.trim().isEmpty,
          optional: _businessNameController.text.trim().isNotEmpty,
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
      // --- Phone & email ---
      SheetFocusScroll(
        child: LabeledTextField(
          label: context.l10n.clients_phone,
          controller: _phoneController,
          keyboard: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumber],
          maxLength: TextLimits.phone,
          errorText: _errors['phone'],
          onChanged: (_) {
            _clearError('phone');
            _clearError('email');
          },
        ),
      ),
      const SizedBox(height: 16),
      SheetFocusScroll(
        child: LabeledTextField(
          label: context.l10n.common_email,
          controller: _emailController,
          keyboard: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          maxLength: TextLimits.email,
          errorText: _errors['email'],
          onChanged: (_) {
            _clearError('email');
            _clearError('phone');
          },
        ),
      ),

      // --- Additional business contacts ---
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
      // --- Address ---
      SheetFocusScroll(
        child: AddressAutocompleteField(
          controller: _addressController,
          required: _businessNameController.text.trim().isEmpty,
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
    ];
  }
}

class _ViewHeader extends StatelessWidget {
  const _ViewHeader({required this.client});

  final ClientRecord client;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      children: [
        AppAvatar(name: client.displayName, size: AvatarSize.lg),
        const SizedBox(height: 12),
        Text(
          client.displayName,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        if (client.name.isNotEmpty && client.name != client.displayName) ...[
          const SizedBox(height: 3),
          Text(
            client.name,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

class _DetailActionBar extends StatelessWidget {
  const _DetailActionBar({
    required this.isEditing,
    required this.isDeleting,
    required this.onSave,
    required this.onDelete,
    required this.onEdit,
  });

  final bool isEditing;
  final bool isDeleting;
  final VoidCallback onSave;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (isEditing) {
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
          const SizedBox(height: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 44),
              foregroundColor: scheme.error,
              side: BorderSide(color: scheme.error),
            ),
            onPressed: onDelete,
            child: Text(context.l10n.common_delete),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: Text(context.l10n.common_edit),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: scheme.error,
              side: BorderSide(color: scheme.error),
            ),
            onPressed: onDelete,
            icon: isDeleting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_outline, size: 18),
            label: Text(
              isDeleting
                  ? context.l10n.clients_deleting
                  : context.l10n.common_delete,
            ),
          ),
        ),
      ],
    );
  }
}

class _ViewContactRow extends StatelessWidget {
  const _ViewContactRow({
    required this.icon,
    required this.text,
    this.onTap,
    this.color,
  });

  final IconData icon;
  final String text;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final effectiveTextColor = color ?? scheme.onSurface;
    final effectiveIconColor = color ?? scheme.onSurfaceVariant;

    final row = InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 17, color: effectiveIconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: effectiveTextColor,
                  height: 1.4,
                ),
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(Icons.open_in_new, size: 14, color: scheme.primary),
              ),
            ],
          ],
        ),
      ),
    );

    if (onTap == null) return row;
    return Semantics(
      button: true,
      label: '$text, ${context.l10n.maps_openAddressWith}',
      child: row,
    );
  }
}
