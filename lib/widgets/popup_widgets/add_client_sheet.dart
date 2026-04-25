import 'package:flutter/material.dart';

import '../../models/client_record.dart';
import '../../services/client_service.dart';
import '../form_widgets/address_autocomplete_field.dart';
import '../form_widgets/labeled_text_field.dart';
import '../sheet_widgets.dart';

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

    final newClient = ClientRecord(
      id: '',
      businessName: _businessNameController.text.trim(),
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      email: email,
      address: _addressController.text.trim(),
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
                onChanged: (_) => _clearError('address'),
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
