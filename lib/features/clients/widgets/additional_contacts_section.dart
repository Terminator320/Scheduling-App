import 'package:flutter/material.dart';

import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/core/validators/text_limits.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/shared/widgets/labeled_text_field.dart';
import 'package:scheduling/shared/widgets/sheet_widgets.dart';

class ContactFields {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController emailController = TextEditingController();

  bool get isEmpty =>
      nameController.text.trim().isEmpty &&
      phoneController.text.trim().isEmpty &&
      emailController.text.trim().isEmpty;

  ClientContact toContact() => ClientContact(
    name: nameController.text.trim(),
    phone: phoneController.text.trim(),
    email: emailController.text.trim(),
  );

  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();
  }
}

class AdditionalContactsSection extends StatelessWidget {
  const AdditionalContactsSection({
    required this.contacts,
    required this.errors,
    required this.onAddContact,
    required this.onRemoveContact,
    required this.onClearError,
    super.key,
  });

  final List<ContactFields> contacts;
  final Map<String, String?> errors;
  final VoidCallback onAddContact;
  final ValueChanged<int> onRemoveContact;
  final ValueChanged<String> onClearError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.clients_additionalBusinessContacts,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onAddContact,
                icon: const Icon(Icons.add),
                label: Text(context.l10n.clients_add),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            context
                .l10n
                .clients_theFirstContactIsTheMainContactAboveAddMoreContactsHereIfNeeded,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (contacts.isEmpty) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onAddContact,
              icon: const Icon(Icons.person_add_alt_1),
              label: Text(context.l10n.clients_addAnotherContact),
            ),
          ],
          for (var i = 0; i < contacts.length; i++) ...[
            const SizedBox(height: 16),
            _AdditionalContactCard(
              index: i,
              contact: contacts[i],
              errors: errors,
              onRemove: () => onRemoveContact(i),
              onClearError: onClearError,
            ),
          ],
        ],
      ),
    );
  }
}

class _AdditionalContactCard extends StatelessWidget {
  const _AdditionalContactCard({
    required this.index,
    required this.contact,
    required this.errors,
    required this.onRemove,
    required this.onClearError,
  });

  final int index;
  final ContactFields contact;
  final Map<String, String?> errors;
  final VoidCallback onRemove;
  final ValueChanged<String> onClearError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${context.l10n.clients_contact} ${index + 2}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: context.l10n.clients_removeContact,
                onPressed: onRemove,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SheetFocusScroll(
            child: LabeledTextField(
              label: context.l10n.clients_contactName,
              controller: contact.nameController,
              required: true,
              autofillHints: const [AutofillHints.name],
              maxLength: TextLimits.personName,
              errorText: errors['contact_${index}_name'],
              onChanged: (_) => onClearError('contact_${index}_name'),
            ),
          ),
          const SizedBox(height: 12),
          SheetFocusScroll(
            child: LabeledTextField(
              label: context.l10n.clients_phone,
              controller: contact.phoneController,
              keyboard: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              maxLength: TextLimits.phone,
              errorText: errors['contact_${index}_phone'],
              onChanged: (_) => onClearError('contact_${index}_phone'),
            ),
          ),
          const SizedBox(height: 12),
          SheetFocusScroll(
            child: LabeledTextField(
              label: context.l10n.common_email,
              controller: contact.emailController,
              keyboard: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              maxLength: TextLimits.email,
              errorText: errors['contact_${index}_email'],
              onChanged: (_) {
                onClearError('contact_${index}_email');
                onClearError('contact_${index}_phone');
              },
            ),
          ),
        ],
      ),
    );
  }
}
