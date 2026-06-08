import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/email_compose_launcher.dart';
import 'package:scheduling/features/maps/address_map_launcher.dart';
import 'package:scheduling/features/maps/domain/address_parser.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/primitives/section_label.dart';
import 'package:url_launcher/url_launcher.dart';

/// Read-only display of a [ClientRecord]: a Call / Email / Directions
/// quick-action row, a contact-info card (tappable phone / email / address)
/// and, for business clients, the saved business contacts.
class ClientDetailViewBody extends ConsumerWidget {
  const ClientDetailViewBody({required this.client, super.key});

  final ClientRecord client;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPhone = client.phone.isNotEmpty;
    final hasEmail = client.email.isNotEmpty;
    final hasAddress = client.address.isNotEmpty;
    final hasContactInfo = hasPhone || hasEmail || hasAddress;

    // Handlers are built here (where `ref` lives) and passed down, so the row
    // and button widgets stay presentational.
    final onCall = hasPhone
        ? () => _launchTel(context, ref, client.phone)
        : null;
    final onEmail = hasEmail
        ? () => EmailComposeLauncher.showEmailChoices(
            context,
            ref,
            email: client.email,
          )
        : null;
    final onDirections = hasAddress
        ? () => AddressMapLauncher.showMapChoices(
            context,
            address: client.address,
          )
        : null;

    // contacts[0] mirrors the primary name/phone/email already shown in the
    // header and contact-info card — only the rest are worth listing again.
    final extraContacts = client.contacts.skip(1).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasContactInfo) ...[
          _QuickActions(
            onCall: onCall,
            onEmail: onEmail,
            onDirections: onDirections,
          ),
          const SizedBox(height: AppSpacing.sp24),
          SectionLabel(context.l10n.clients_contactInfo),
          const SizedBox(height: AppSpacing.sp8),
          _InfoCard(
            rows: [
              if (hasPhone)
                _ContactRow(
                  icon: Icons.phone_outlined,
                  text: client.phone,
                  onTap: onCall,
                  trailingIcon: Icons.chevron_right,
                ),
              if (hasEmail)
                _ContactRow(
                  icon: Icons.email_outlined,
                  text: client.email,
                  onTap: onEmail,
                  trailingIcon: Icons.chevron_right,
                ),
              if (hasAddress)
                _ContactRow(
                  icon: Icons.location_on_outlined,
                  text: AddressParser.canonicalToDisplay(client.address),
                  onTap: onDirections,
                  trailingIcon: Icons.open_in_new,
                  semanticLabel:
                      '${AddressParser.canonicalToDisplay(client.address)}, '
                      '${context.l10n.maps_openAddressWith}',
                ),
            ],
          ),
        ],
        // --- Additional business contacts ---
        if (extraContacts.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sp24),
          SectionLabel(context.l10n.common_contacts),
          const SizedBox(height: AppSpacing.sp8),
          for (final contact in extraContacts)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sp8),
              child: _InfoCard(
                rows: [
                  if (contact.name.isNotEmpty)
                    _ContactRow(
                      icon: Icons.person_outline,
                      text: contact.name,
                      iconColor: Theme.of(context).colorScheme.secondary,
                      emphasize: true,
                    ),
                  if (contact.phone.isNotEmpty)
                    _ContactRow(
                      icon: Icons.phone_outlined,
                      text: contact.phone,
                      onTap: () => _launchTel(context, ref, contact.phone),
                      trailingIcon: Icons.chevron_right,
                    ),
                  if (contact.email.isNotEmpty)
                    _ContactRow(
                      icon: Icons.email_outlined,
                      text: contact.email,
                      onTap: () => EmailComposeLauncher.showEmailChoices(
                        context,
                        ref,
                        email: contact.email,
                      ),
                      trailingIcon: Icons.chevron_right,
                    ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

Future<void> _launchTel(BuildContext context, WidgetRef ref, String phone) {
  return _launch(
    context,
    ref,
    Uri(scheme: 'tel', path: phone.trim()),
    context.l10n.error_couldNotStartCall,
  );
}

Future<void> _launch(
  BuildContext context,
  WidgetRef ref,
  Uri uri,
  String errorMessage,
) async {
  try {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ref.read(noticeServiceProvider).error(errorMessage);
    }
  } catch (_) {
    if (context.mounted) ref.read(noticeServiceProvider).error(errorMessage);
  }
}

/// Call / Email / Directions buttons. Each appears only when its handler is
/// non-null (i.e. the client has that detail).
class _QuickActions extends StatelessWidget {
  const _QuickActions({this.onCall, this.onEmail, this.onDirections});

  final VoidCallback? onCall;
  final VoidCallback? onEmail;
  final VoidCallback? onDirections;

  @override
  Widget build(BuildContext context) {
    final buttons = [
      if (onCall != null)
        _QuickActionButton(
          icon: Icons.phone_outlined,
          label: context.l10n.clients_call,
          onTap: onCall!,
        ),
      if (onEmail != null)
        _QuickActionButton(
          icon: Icons.email_outlined,
          label: context.l10n.common_email,
          onTap: onEmail!,
        ),
      if (onDirections != null)
        _QuickActionButton(
          icon: Icons.directions_outlined,
          label: context.l10n.clients_directions,
          onTap: onDirections!,
        ),
    ];

    if (buttons.isEmpty) return const SizedBox.shrink();

    return Row(
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.sp8),
          Expanded(child: buttons[i]),
        ],
      ],
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.r12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(AppRadius.r12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: scheme.onPrimaryContainer),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bordered card that stacks [rows] with a hairline divider between each pair.
class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.rows});

  final List<_ContactRow> rows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadius.r16),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.r16),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 60),
              rows[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// One row inside an [_InfoCard]: a tinted icon chip, the value, and an
/// optional trailing affordance. Tappable when [onTap] is non-null.
class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.text,
    this.iconColor,
    this.onTap,
    this.trailingIcon,
    this.emphasize = false,
    this.semanticLabel,
  });

  final IconData icon;
  final String text;
  final Color? iconColor;
  final VoidCallback? onTap;
  final IconData? trailingIcon;

  /// Renders the value as a bold title (used for a contact's name row).
  final bool emphasize;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chipColor = iconColor ?? scheme.primary;

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: chipColor.withValues(alpha: theme.cardStyle.iconChipAlpha),
              borderRadius: BorderRadius.circular(AppRadius.r8),
            ),
            child: Icon(icon, size: 18, color: chipColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: emphasize
                  ? theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    )
                  : theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurface,
                      height: 1.3,
                    ),
            ),
          ),
          if (trailingIcon != null) ...[
            const SizedBox(width: 8),
            Icon(trailingIcon, size: 18, color: scheme.onSurfaceVariant),
          ],
        ],
      ),
    );

    if (onTap == null) return content;

    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}
