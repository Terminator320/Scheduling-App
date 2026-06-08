import 'package:flutter/material.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/maps/address_map_launcher.dart';
import 'package:scheduling/features/maps/domain/address_parser.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/primitives/section_label.dart';

/// Read-only display of a [ClientRecord]: a contact-info card (phone / email /
/// tappable address) plus, for business clients, the saved business contacts.
class ClientDetailViewBody extends StatelessWidget {
  const ClientDetailViewBody({required this.client, super.key});

  final ClientRecord client;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasContactInfo =
        client.phone.isNotEmpty ||
        client.email.isNotEmpty ||
        client.address.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // --- Contact info card ---
        if (hasContactInfo)
          _ViewContactCard(
            rows: [
              if (client.phone.isNotEmpty)
                _ViewContactRow(icon: Icons.phone_outlined, text: client.phone),
              if (client.email.isNotEmpty)
                _ViewContactRow(icon: Icons.email_outlined, text: client.email),
              if (client.address.isNotEmpty)
                _ViewContactRow(
                  icon: Icons.location_on_outlined,
                  text: AddressParser.canonicalToDisplay(client.address),
                  onTap: () => AddressMapLauncher.showMapChoices(
                    context,
                    address: client.address,
                  ),
                  color: scheme.primary,
                ),
            ],
          ),
        // --- Business contacts list ---
        if (client.contacts.isNotEmpty) ...[
          const SizedBox(height: 24),
          SectionLabel(context.l10n.common_contacts),
          const SizedBox(height: 8),
          ...client.contacts.map(
            (contact) => _ViewContactCard(
              margin: const EdgeInsets.only(bottom: 8),
              rows: [
                if (contact.name.isNotEmpty)
                  _ViewContactRow(
                    icon: Icons.person_outline,
                    text: contact.name,
                  ),
                if (contact.phone.isNotEmpty)
                  _ViewContactRow(
                    icon: Icons.phone_outlined,
                    text: contact.phone,
                  ),
                if (contact.email.isNotEmpty)
                  _ViewContactRow(
                    icon: Icons.email_outlined,
                    text: contact.email,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Bordered card of contact rows with a divider between each pair — shared
/// by the contact-info card and the business-contact cards.
class _ViewContactCard extends StatelessWidget {
  const _ViewContactCard({required this.rows, this.margin});

  final List<_ViewContactRow> rows;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.r12),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 48),
              rows[i],
            ],
          ],
        ),
      ),
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
