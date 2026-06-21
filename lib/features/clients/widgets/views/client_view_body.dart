import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/launchers/phone_call_launcher.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/clients/contact_export_launcher.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/email_compose_launcher.dart';
import 'package:scheduling/features/clients/widgets/cards/client_contacts_cards.dart';
import 'package:scheduling/features/maps/address_map_launcher.dart';
import 'package:scheduling/features/maps/domain/address_parser.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/cards/info_card.dart';
import 'package:scheduling/shared/widgets/primitives/quick_action_button.dart';
import 'package:scheduling/shared/widgets/primitives/section_label.dart';

/// Read-only display of a [ClientRecord]: a Call / Email / Directions
/// quick-action row, a contact-info card (tappable phone / email / address)
/// and, for business clients, the saved business contacts.
class ClientDetailViewBody extends ConsumerWidget {
  const ClientDetailViewBody({required this.client, super.key});

  final ClientRecord client;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPhone = client.phone.isNotEmpty;
    final hasMobile = client.mobile.isNotEmpty;
    final hasEmail = client.email.isNotEmpty;
    final hasAddress = client.address.isNotEmpty;
    final fullName = [
      client.firstName,
      client.lastName,
    ].where((part) => part.trim().isNotEmpty).join(' ').trim();
    // The person name is worth showing only when it adds info beyond the
    // customer/display name already in the header.
    final hasPersonName = fullName.isNotEmpty && fullName != client.name;
    final hasContactInfo =
        hasPersonName || hasPhone || hasMobile || hasEmail || hasAddress;

    // Handlers are built here (where `ref` lives) and passed down, so the row
    // and button widgets stay presentational.
    final onCall = hasPhone
        ? () => launchPhoneCall(context, ref, client.phone)
        : null;
    final onMobile = hasMobile
        ? () => launchPhoneCall(context, ref, client.mobile)
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

    // `contacts` holds only the extra contacts (the customer's own details
    // live in the header and contact-info card).
    final extraContacts = client.contacts;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QuickActionsRow(
          buttons: [
            if (onCall != null)
              QuickActionButton(
                icon: Icons.phone_outlined,
                label: context.l10n.clients_call,
                onTap: onCall,
              ),
            if (onEmail != null)
              QuickActionButton(
                icon: Icons.email_outlined,
                label: context.l10n.common_email,
                onTap: onEmail,
              ),
            if (onDirections != null)
              QuickActionButton(
                icon: Icons.directions_outlined,
                label: context.l10n.clients_directions,
                onTap: onDirections,
              ),
            QuickActionButton(
              icon: Icons.person_add_alt_1_outlined,
              label: context.l10n.clients_saveToContacts,
              onTap: onSaveToContacts,
            ),
          ],
        ),
        if (hasContactInfo) ...[
          const SizedBox(height: AppSpacing.sp24),
          SectionLabel(context.l10n.clients_contactInfo),
          const SizedBox(height: AppSpacing.sp8),
          InfoCard(
            rows: [
              if (hasPersonName)
                InfoCardRow(
                  icon: Icons.person_outline,
                  text: fullName,
                ),
              if (hasPhone)
                InfoCardRow(
                  icon: Icons.phone_outlined,
                  text: client.phone,
                  onTap: onCall,
                  trailingIcon: Icons.chevron_right,
                ),
              if (hasMobile)
                InfoCardRow(
                  icon: Icons.smartphone_outlined,
                  text: client.mobile,
                  onTap: onMobile,
                  trailingIcon: Icons.chevron_right,
                ),
              if (hasEmail)
                InfoCardRow(
                  icon: Icons.email_outlined,
                  text: client.email,
                  onTap: onEmail,
                  trailingIcon: Icons.chevron_right,
                ),
              if (hasAddress)
                InfoCardRow(
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
        ClientContactsCards(contacts: extraContacts),
      ],
    );
  }
}
