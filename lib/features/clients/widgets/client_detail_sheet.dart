import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/maps/address_map_launcher.dart';
import 'package:scheduling/shared/widgets/address_autocomplete_field.dart';
import 'package:scheduling/shared/widgets/app_avatar.dart';
import 'package:scheduling/shared/widgets/labeled_text_field.dart';
import 'package:scheduling/shared/widgets/sheet_widgets.dart';

class _ParsedAptAddress {
  final String apt;
  final String street;

  const _ParsedAptAddress({required this.apt, required this.street});
}

class ClientDetailSheet extends ConsumerStatefulWidget {
  final ClientRecord client;

  const ClientDetailSheet({super.key, required this.client});

  @override
  ConsumerState<ClientDetailSheet> createState() => _ClientDetailSheetState();
}

class _ClientDetailSheetState extends ConsumerState<ClientDetailSheet> {
  bool _isEditing = false;
  bool _isDeleting = false;
  final Map<String, String?> _errors = {};

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

  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

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

  String _extractAptFromAddress(String address) {
    return _splitAptFromAddress(address)?.apt ?? '';
  }

  String _stripAptFromAddress(String address) {
    return _splitAptFromAddress(address)?.street ?? address;
  }

  String _addressWithVisualApt(String street, String apt) {
    final cleanStreet = street.trim();
    final cleanApt = apt.trim().replaceAll(RegExp(r'^#+'), '');
    if (cleanStreet.isEmpty || cleanApt.isEmpty) return cleanStreet;

    final commaIndex = cleanStreet.indexOf(',');
    if (commaIndex == -1) {
      return '$cleanApt-$cleanStreet';
    }

    final firstLine = cleanStreet.substring(0, commaIndex).trim();
    final rest = cleanStreet.substring(commaIndex);
    return '$cleanApt-$firstLine$rest';
  }

  String _buildFullAddress() {
    final parsedAddress = _splitAptFromAddress(_addressController.text);
    final street = (parsedAddress?.street ?? _addressController.text).trim();
    final apt = _aptController.text.trim().isNotEmpty
        ? _aptController.text.trim()
        : (parsedAddress?.apt ?? '').trim();

    return _addressWithVisualApt(street, apt);
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
    _addressController = TextEditingController(
      text: _stripAptFromAddress(c.address),
    );
    _aptController = TextEditingController(
      text: c.apt.isNotEmpty ? c.apt : _extractAptFromAddress(c.address),
    );
    _cityController = TextEditingController(text: c.city);
    _provinceController = TextEditingController(text: c.province);
    _countryController = TextEditingController(text: c.country);
    _postalCodeController = TextEditingController(text: c.postalCode);
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
    super.dispose();
  }

  void _clearError(String key) {
    if (_errors[key] != null) setState(() => _errors[key] = null);
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
    final hasBusinessOrName = businessName.isNotEmpty || name.isNotEmpty;
    final hasContactMethod = phone.isNotEmpty || email.isNotEmpty;

    setState(() {
      _errors['businessName'] = !hasBusinessOrName
          ? context.l10n.businessNameOrContactNameIsRequired
          : null;
      _errors['name'] = !hasBusinessOrName
          ? context.l10n.businessNameOrContactNameIsRequired
          : null;
      _errors['phone'] = !hasContactMethod
          ? context.l10n.phoneOrEmailIsRequired
          : null;
      _errors['email'] = email.isNotEmpty && !_emailRegex.hasMatch(email)
          ? context.l10n.enterAValidEmail
          : null;
      _errors['address'] = businessName.isEmpty && address.isEmpty
          ? context.l10n.addressIsRequired
          : null;
    });

    if (_errors.values.any((e) => e != null)) return;

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
      contacts: widget.client.contacts,
    );

    try {
      await ref.read(clientsRepositoryProvider).updateClient(updated);
      if (mounted) setState(() => _isEditing = false);
    } catch (_) {
      if (!mounted) return;
      ref
          .read(noticeServiceProvider)
          .error(context.l10n.couldNotSaveChangesTryAgain);
    }
  }

  Future<void> _confirmDelete() async {
    final clientName = widget.client.displayName.isNotEmpty
        ? widget.client.displayName
        : context.l10n.thisClient;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: Text(dialogContext.l10n.deleteClient),
          content: Text(
            '${dialogContext.l10n.areYouSureYouWantToDelete} $clientName? ${dialogContext.l10n.thisCannotBeUndone}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(dialogContext.l10n.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(dialogContext.l10n.delete),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true || !mounted) return;

    setState(() => _isDeleting = true);

    final notices = ref.read(noticeServiceProvider);
    try {
      await ref.read(clientsRepositoryProvider).deleteClient(widget.client.id);
      if (!mounted) return;
      Navigator.pop(context);
      notices.success(context.l10n.clientDeletedSuccessfully);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isDeleting = false);
      notices.error(context.l10n.couldNotDeleteClientTryAgain);
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
            _isEditing
                ? Text(
                    context.l10n.editClient,
                    style: theme.textTheme.headlineLarge,
                  )
                : _buildViewHeader(theme),
            const SizedBox(height: 20),
            const Divider(height: 1),
            const SizedBox(height: 20),
            if (_isEditing)
              ..._buildEditFields()
            else
              ..._buildViewFields(theme),
            const SizedBox(height: 24),
            _buildActionButtons(),
          ],
        );
      },
    );
  }

  Widget _buildViewHeader(ThemeData theme) {
    final c = widget.client;
    final scheme = theme.colorScheme;
    return Column(
      children: [
        AppAvatar(name: c.displayName, size: AvatarSize.lg),
        const SizedBox(height: 12),
        Text(
          c.displayName,
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        if (c.name.isNotEmpty && c.name != c.displayName) ...[
          const SizedBox(height: 3),
          Text(
            c.name,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  List<Widget> _buildViewFields(ThemeData theme) {
    final c = widget.client;
    final scheme = theme.colorScheme;
    final hasContactInfo =
        c.phone.isNotEmpty || c.email.isNotEmpty || c.address.isNotEmpty;

    return [
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
                    text: c.address,
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
      if (c.contacts.isNotEmpty) ...[
        const SizedBox(height: 24),
        Text(
          context.l10n.contacts.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant,
            letterSpacing: 0.7,
          ),
        ),
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
              if (contact.email.isNotEmpty) const Divider(height: 1, indent: 48),
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
      // Avatar header
      Row(
        children: [
          AppAvatar(name: widget.client.displayName, size: AvatarSize.lg),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.client.displayName,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      const Divider(height: 1),
      const SizedBox(height: 14),

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
          required: _businessNameController.text.trim().isEmpty,
          optional: _businessNameController.text.trim().isNotEmpty,
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
      const SizedBox(height: 16),
      SheetFocusScroll(
        child: AddressAutocompleteField(
          controller: _addressController,
          required: _businessNameController.text.trim().isEmpty,
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
    ];
  }

  Widget _buildActionButtons() {
    if (_isEditing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 46),
            ),
            onPressed: _save,
            child: Text(context.l10n.saveChanges),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 44),
              foregroundColor: Theme.of(context).colorScheme.error,
              side: BorderSide(color: Theme.of(context).colorScheme.error),
            ),
            onPressed: _isDeleting ? null : _confirmDelete,
            child: Text(context.l10n.delete),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _isDeleting
                ? null
                : () => setState(() => _isEditing = true),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: Text(context.l10n.edit),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
              side: BorderSide(color: Theme.of(context).colorScheme.error),
            ),
            onPressed: _isDeleting ? null : _confirmDelete,
            icon: _isDeleting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_outline, size: 18),
            label: Text(
              _isDeleting ? context.l10n.deleting : context.l10n.delete,
            ),
          ),
        ),
      ],
    );
  }
}

class _ViewContactRow extends StatelessWidget {
  const _ViewContactRow({required this.icon, required this.text, this.onTap, this.color});

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

    return InkWell(
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
                child: Icon(
                  Icons.open_in_new,
                  size: 14,
                  color: scheme.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
