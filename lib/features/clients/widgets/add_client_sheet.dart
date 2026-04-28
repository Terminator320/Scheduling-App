import 'package:flutter/material.dart';

import 'package:scheduling/features/clients/models/client_record.dart';
import 'package:scheduling/features/clients/services/client_service.dart';
import 'package:scheduling/shared/widgets/address_autocomplete_field.dart';
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

class AddClientSheet extends StatefulWidget {
  const AddClientSheet({super.key});

  @override
  State<AddClientSheet> createState() => _AddClientSheetState();
}

class _AddClientSheetState extends State<AddClientSheet> {
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


  final _clientService = ClientService();
  final Map<String, String?> _errors = {};
  bool _isSaving = false;

  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

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
    super.dispose();
  }

  String? _validateEmail(String value) {
    if (value.isEmpty) return null;
    if (!_emailRegex.hasMatch(value)) return "Enter a valid email";
    return null;
  }

  void _clearError(String key) {
    if (_errors[key] != null) setState(() => _errors[key] = null);
  }

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

  String _addressWithVisualApt(String street, String apt) {
    var cleanStreet = street.trim();

    // 🔥 REMOVE any existing unit (#, Apt, Unit, etc.)
    cleanStreet = cleanStreet.replaceAll(
      RegExp(r'\s+(#|apt\.?|apartment|unit|suite|ste\.?)\s*[-#: ]*\s*[A-Za-z0-9 /]+', caseSensitive: false),
      '',
    ).trim();

    final cleanApt = apt.trim().replaceAll(RegExp(r'^#+'), '');
    if (cleanStreet.isEmpty || cleanApt.isEmpty) return cleanStreet;

    final commaIndex = cleanStreet.indexOf(',');

    // 👇 If no city part yet
    if (commaIndex == -1) {
      return '$cleanStreet #$cleanApt';
    }

    // 👇 Insert before city
    final firstLine = cleanStreet.substring(0, commaIndex).trim();
    final rest = cleanStreet.substring(commaIndex);

    return '$firstLine #$cleanApt$rest';
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
    final email = _emailController.text.trim();
    setState(() {
      _errors['name'] = _nameController.text.trim().isEmpty
          ? "Contact name is required"
          : null;
      _errors['phone'] = _phoneController.text.trim().isEmpty
          ? "Phone is required"
          : null;
      _errors['email'] = _validateEmail(email);
    });

    if (_errors.values.any((e) => e != null)) return;

    setState(() => _isSaving = true);

    final parsedAddress = _splitAptFromAddress(_addressController.text);
    final street = (parsedAddress?.street ?? _addressController.text).trim();
    final apt = _aptController.text.trim().isNotEmpty
        ? _aptController.text.trim()
        : (parsedAddress?.apt ?? '').trim();
    final fullAddress = _addressWithVisualApt(street, apt);

    final newClient = ClientRecord(
      id: '',
      businessName: _businessNameController.text.trim(),
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      email: email,
      address: fullAddress,
      apt: apt,
      city: _cityController.text.trim(),
      province: _provinceController.text.trim(),
      country: _countryController.text.trim(),
      postalCode: _postalCodeController.text.trim(),
      contacts: [],
    );

    try {
      await _clientService.addClient(newClient);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not add client. Try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SheetHandle(),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  "New client",
                  style: theme.textTheme.headlineLarge,
                ),
              ),
              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 20),
              LabeledTextField(
                label: "Business name",
                controller: _businessNameController,
                optional: true,
                autofillHints: const [AutofillHints.organizationName],
              ),
              const SizedBox(height: 16),
              LabeledTextField(
                label: "Contact name",
                controller: _nameController,
                required: true,
                autofillHints: const [AutofillHints.name],
                errorText: _errors['name'],
                onChanged: (_) => _clearError('name'),
              ),
              const SizedBox(height: 16),
              LabeledTextField(
                label: "Phone",
                controller: _phoneController,
                required: true,
                keyboard: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                errorText: _errors['phone'],
                onChanged: (_) => _clearError('phone'),
              ),
              const SizedBox(height: 16),
              LabeledTextField(
                label: "Email",
                controller: _emailController,
                keyboard: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                errorText: _errors['email'],
                onChanged: (_) => _clearError('email'),
              ),
              const SizedBox(height: 16),
              AddressAutocompleteField(
                controller: _addressController,
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
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.pop(context),
                      child: const Text("Cancel"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
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
                          : const Text("Add client"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
