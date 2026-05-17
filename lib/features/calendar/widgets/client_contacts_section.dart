import 'package:flutter/material.dart';

import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/utils/l10n_extensions.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';

class ClientContactsSection extends StatelessWidget {
  const ClientContactsSection({required this.contacts, super.key});

  final List<ClientContact> contacts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sp12, left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.contacts,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: AppSpacing.sp8),
          ...contacts.map((c) => _ContactCard(contact: c)),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.contact});

  final ClientContact contact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(AppSpacing.sp12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (contact.name.trim().isNotEmpty)
            _line(theme, scheme, Icons.person_outline, contact.name.trim()),
          if (contact.phone.trim().isNotEmpty)
            _line(theme, scheme, Icons.phone_outlined, contact.phone.trim()),
          if (contact.email.trim().isNotEmpty)
            _line(theme, scheme, Icons.mail_outline, contact.email.trim()),
        ],
      ),
    );
  }

  Widget _line(
    ThemeData theme,
    ColorScheme scheme,
    IconData icon,
    String text,
  ) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
              ),
            ),
          ],
        ),
      );
}
