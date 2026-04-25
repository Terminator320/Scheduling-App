import 'package:flutter/material.dart';

import '../../models/client_record.dart';
import '../../services/client_service.dart';
import '../form_widgets/address_autocomplete_field.dart';
import '../form_widgets/form_helpers.dart';
import '../form_widgets/labeled_text_field.dart';
import '../list_widgets/info_row.dart';
import '../sheet_widgets.dart';

class ClientDetailSheet extends StatefulWidget {
  final ClientRecord client;

  const ClientDetailSheet({super.key, required this.client});

  @override
  State<ClientDetailSheet> createState() => _ClientDetailSheetState();
}

class _ClientDetailSheetState extends State<ClientDetailSheet> {
  bool _isEditing = false;
  final Map<String, String?> _errors = {};

  late final TextEditingController _businessNameController;
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _addressController;

  final _clientService = ClientService();

  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void initState() {
    super.initState();
    final c = widget.client;
    _businessNameController = TextEditingController(text: c.businessName);
    _nameController = TextEditingController(text: c.name);
    _phoneController = TextEditingController(text: c.phone);
    _emailController = TextEditingController(text: c.email);
    _addressController = TextEditingController(text: c.address);
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _clearError(String key) {
    if (_errors[key] != null) setState(() => _errors[key] = null);
  }

  void _cancelEdit() {
    final c = widget.client;
    setState(() {
      _isEditing = false;
      _businessNameController.text = c.businessName;
      _nameController.text = c.name;
      _phoneController.text = c.phone;
      _emailController.text = c.email;
      _addressController.text = c.address;
      _errors.clear();
    });
  }

  Future<void> _save() async {
    final email = _emailController.text.trim();
    setState(() {
      _errors['name'] = _nameController.text.trim().isEmpty
          ? "Name is required"
          : null;
      _errors['phone'] = _phoneController.text.trim().isEmpty
          ? "Phone is required"
          : null;
      _errors['email'] = email.isEmpty
          ? "Email is required"
          : (!_emailRegex.hasMatch(email) ? "Enter a valid email" : null);
      _errors['address'] = _addressController.text.trim().isEmpty
          ? "Address is required"
          : null;
    });

    if (_errors.values.any((e) => e != null)) return;

    final updated = ClientRecord(
      id: widget.client.id,
      businessName: _businessNameController.text.trim(),
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      email: email,
      address: _addressController.text.trim(),
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
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
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
                if (_isEditing)
                  ..._buildEditFields()
                else
                  ..._buildViewFields(theme),
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
              Text(
                c.displayName,
                style: theme.textTheme.headlineLarge,
              ),
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
        InfoRow(icon: Icons.location_on_outlined, text: c.address),
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
        required: true,
        keyboard: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        errorText: _errors['email'],
        onChanged: (_) => _clearError('email'),
      ),
      const SizedBox(height: 16),
      AddressAutocompleteField(
        controller: _addressController,
        required: true,
        errorText: _errors['address'],
        onChanged: (_) => _clearError('address'),
        onAddressSelected: (_) => _clearError('address'),
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

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onPressed: () => setState(() => _isEditing = true),
        icon: const Icon(Icons.edit_outlined, size: 18),
        label: const Text("Edit"),
      ),
    );
  }
}
