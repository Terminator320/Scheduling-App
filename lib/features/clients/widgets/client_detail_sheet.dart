import 'package:flutter/material.dart';

import 'package:scheduling/features/clients/models/client_record.dart';
import 'package:scheduling/features/clients/services/client_service.dart';
import 'package:scheduling/features/maps/address_map_launcher.dart';
import 'package:scheduling/shared/widgets/address_autocomplete_field.dart';
import 'package:scheduling/shared/widgets/form_helpers.dart';
import 'package:scheduling/shared/widgets/info_row.dart';
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

class ClientDetailSheet extends StatefulWidget {
  final ClientRecord client;

  const ClientDetailSheet({super.key, required this.client});

  @override
  State<ClientDetailSheet> createState() => _ClientDetailSheetState();
}

class _ClientDetailSheetState extends State<ClientDetailSheet> {
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

  final _clientService = ClientService();

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
      return '$cleanStreet #$cleanApt';
    }

    final firstLine = cleanStreet.substring(0, commaIndex).trim();
    final rest = cleanStreet.substring(commaIndex);
    return '$firstLine #$cleanApt$rest';
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
    _addressController = TextEditingController(text: _stripAptFromAddress(c.address));
    _aptController = TextEditingController(text: c.apt.isNotEmpty ? c.apt : _extractAptFromAddress(c.address));
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

  void _cancelEdit() {
    final c = widget.client;
    setState(() {
      _isEditing = false;
      _businessNameController.text = c.businessName;
      _nameController.text = c.name;
      _phoneController.text = c.phone;
      _emailController.text = c.email;
      _addressController.text = _stripAptFromAddress(c.address);
      _aptController.text = c.apt.isNotEmpty ? c.apt : _extractAptFromAddress(c.address);
      _cityController.text = c.city;
      _provinceController.text = c.province;
      _countryController.text = c.country;
      _postalCodeController.text = c.postalCode;
      _errors.clear();
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
          ? "Business name or contact name is required"
          : null;
      _errors['name'] = !hasBusinessOrName
          ? "Business name or contact name is required"
          : null;
      _errors['phone'] = !hasContactMethod
          ? "Phone or email is required"
          : null;
      _errors['email'] = email.isNotEmpty && !_emailRegex.hasMatch(email)
          ? "Enter a valid email"
          : null;
      _errors['address'] = businessName.isEmpty && address.isEmpty
          ? "Address is required"
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
      await _clientService.updateClient(updated);
      if (mounted) setState(() => _isEditing = false);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not save changes. Try again.")),
      );
    }
  }

  Future<void> _confirmDelete() async {
    final clientName = widget.client.displayName.isNotEmpty
        ? widget.client.displayName
        : 'this client';

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: const Text('Delete client?'),
          content: Text(
            'Are you sure you want to delete $clientName? This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true || !mounted) return;

    setState(() => _isDeleting = true);

    try {
      await _clientService.deleteClient(widget.client.id);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Client deleted successfully.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isDeleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete client. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (sheetContext, scrollController) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(sheetContext).unfocus(),
          child: Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: ListView(
              controller: scrollController,
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 12,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
              ),
              children: [
                const SheetHandle(),
                const SizedBox(height: 16),
                _isEditing
                    ? Text(
                        "Edit client",
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineLarge,
                      )
                    : _buildViewHeader(theme),
                const SizedBox(height: 20),
                const Divider(height: 1),
                const SizedBox(height: 20),
                if (_isEditing) ..._buildEditFields() else ..._buildViewFields(theme),
                const SizedBox(height: 24),
                _buildActionButtons(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildViewHeader(ThemeData theme) {
    final c = widget.client;
    final scheme = theme.colorScheme;
    return Row(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: scheme.primaryContainer,
          child: Text(
            c.displayName.isNotEmpty ? c.displayName[0].toUpperCase() : '?',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.displayName, style: theme.textTheme.headlineLarge),
              if (c.name.isNotEmpty && c.name != c.displayName) ...[
                const SizedBox(height: 2),
                Text(
                  c.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildViewFields(ThemeData theme) {
    final c = widget.client;
    final scheme = theme.colorScheme;

    return [
      if (c.phone.isNotEmpty)
        InfoRow(icon: Icons.phone_outlined, text: c.phone),

      if (c.email.isNotEmpty)
        InfoRow(icon: Icons.email_outlined, text: c.email),

      if (c.address.isNotEmpty)
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => AddressMapLauncher.showMapChoices(
            context,
            address: c.address,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: InfoRow(
              icon: Icons.location_on_outlined,
              text: c.address,
              iconColor: Theme.of(context).colorScheme.primary.withOpacity(0.9),
              textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                height: 1.4,
                color: Theme.of(context).colorScheme.primary.withOpacity(0.9),
              ),
            ),
          ),
        ),

      if (c.contacts.isNotEmpty) ...[
        const SizedBox(height: 24),
        formSectionLabel(context, "Contacts"),
        const SizedBox(height: 8),
        ...c.contacts.map(
              (contact) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (contact.name.isNotEmpty)
                  InfoRow(icon: Icons.person_outline, text: contact.name),
                if (contact.phone.isNotEmpty)
                  InfoRow(icon: Icons.phone_outlined, text: contact.phone),
                if (contact.email.isNotEmpty)
                  InfoRow(icon: Icons.mail_outline, text: contact.email),
              ],
            ),
          ),
        ),
      ],
    ];
  }

  List<Widget> _buildEditFields() {
    return [
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
      const SizedBox(height: 16),
      AddressAutocompleteField(
        controller: _addressController,
        required: _businessNameController.text.trim().isEmpty,
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
    ];
  }

  Widget _buildActionButtons() {
    if (_isEditing) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _cancelEdit,
              child: const Text("Cancel"),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _save,
              child: const Text("Save changes"),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
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
            label: Text(_isDeleting ? "Deleting..." : "Delete"),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _isDeleting ? null : () => setState(() => _isEditing = true),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text("Edit"),
          ),
        ),
      ],
    );
  }
}
