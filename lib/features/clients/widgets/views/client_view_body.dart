import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/launchers/phone_call_launcher.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/clients/contact_export_launcher.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/email_compose_launcher.dart';
import 'package:scheduling/features/clients/widgets/cards/client_contacts_cards.dart';
import 'package:scheduling/features/clients/widgets/sections/client_job_history_section.dart';
import 'package:scheduling/features/maps/address_map_launcher.dart';
import 'package:scheduling/features/maps/domain/address_parser.dart';
import 'package:scheduling/features/wave/widgets/wave_sync_badge.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/cards/key_value_panel.dart';
import 'package:scheduling/shared/widgets/primitives/quick_action_button.dart';

/// Read-only display of a ClientRecord — three action tiles, a keyed info panel
/// and an additional-contacts section.
class ClientDetailViewBody extends ConsumerWidget {
  const ClientDetailViewBody({
    required this.client,
    required this.onBookJob,
    super.key,
  });

  final ClientRecord client;

  /// Opens the new-appointment sheet seeded with this client. Supplied by the
  /// host, which owns the navigator context.
  final VoidCallback onBookJob;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPhone = client.phone.isNotEmpty;
    final hasEmail = client.email.isNotEmpty;
    final hasAddress = client.address.isNotEmpty;
    final displayAddress = AddressParser.canonicalToDisplay(client.address);

    // Handlers built here (where `ref` lives) so widgets stay presentational.
    final onCall = hasPhone
        ? () => launchPhoneCall(context, ref, client.phone)
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
    // Always offered — even a name-only client is worth saving to the phone.
    void onSaveToContacts() => saveClientToPhoneContacts(context, ref, client);

    // `contacts` holds only the extra contacts — the customer's own details already
    // live in the header and the info panel.
    final extraContacts = client.contacts;

    final hasSyncBadge = client.waveSyncState.isNotEmpty;

    final billingLine = [
      client.billingTerms,
      if (client.autoInvoice) context.l10n.clients_autoInvoice,
    ].where((v) => v.trim().isNotEmpty).join(' · ');

    final infoRows = _infoRows(
      context,
      displayAddress: displayAddress,
      billingLine: billingLine,
      onCall: onCall,
      onEmail: onEmail,
      onDirections: onDirections,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Exactly three tiles by design. Save-to-contacts moves below the panel
        // rather than competing for a tile slot.
        QuickActionsRow(
          buttons: [
            if (onCall != null)
              QuickActionButton(
                icon: Icons.phone_outlined,
                label: context.l10n.clients_call,
                onTap: onCall,
              ),
            if (onDirections != null)
              QuickActionButton(
                icon: Icons.directions_outlined,
                label: context.l10n.clients_directions,
                onTap: onDirections,
              ),
            QuickActionButton(
              icon: Icons.event_available_outlined,
              label: context.l10n.clients_bookJob,
              onTap: onBookJob,
            ),
          ],
        ),
        if (infoRows.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sp24),
          KeyValuePanel(rows: infoRows),
        ],
        const SizedBox(height: AppSpacing.sp16),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: onSaveToContacts,
            icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
            label: Text(context.l10n.clients_saveToContacts),
          ),
        ),
        ClientContactsCards(contacts: extraContacts),
        const SizedBox(height: AppSpacing.sp24),
        ClientJobHistorySection(clientId: client.id),
        if (hasSyncBadge) ...[
          const SizedBox(height: AppSpacing.sp16),
          Align(
            alignment: Alignment.centerLeft,
            child: WaveSyncBadge(
              syncState: client.waveSyncState,
              syncError: client.waveSyncError,
            ),
          ),
        ],
      ],
    );
  }

  /// Empty rows are omitted entirely — a read-only detail body never renders
  /// "None" placeholders.
  List<KeyValueRow> _infoRows(
    BuildContext context, {
    required String displayAddress,
    required String billingLine,
    VoidCallback? onCall,
    VoidCallback? onEmail,
    VoidCallback? onDirections,
  }) => [
    if (client.phone.isNotEmpty)
      KeyValueRow(
        label: context.l10n.clients_phoneKey,
        value: client.phone,
        onTap: onCall,
        emphasize: true,
      ),
    if (client.email.isNotEmpty)
      KeyValueRow(
        label: context.l10n.clients_emailKey,
        value: client.email,
        onTap: onEmail,
        emphasize: true,
      ),
    if (client.address.isNotEmpty)
      KeyValueRow(
        label: context.l10n.clients_addressKey,
        value: displayAddress,
        onTap: onDirections,
        emphasize: true,
        semanticLabel: '$displayAddress, ${context.l10n.maps_openAddressWith}',
      ),
    if (client.onSiteManager.trim().isNotEmpty)
      KeyValueRow(
        label: context.l10n.clients_manager,
        value: client.onSiteManager,
      ),
    if (billingLine.isNotEmpty)
      KeyValueRow(label: context.l10n.clients_billingKey, value: billingLine),
  ];
}
