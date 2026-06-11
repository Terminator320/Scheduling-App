import 'package:flutter/widgets.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/features/clients/data/contact_link_store.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/maps/domain/address_parser.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Saves [client] into the device's contacts.
///
/// With the Contacts permission granted, the contact is written directly and
/// the resulting native id is linked to the client (via [ContactLinkStore]) so
/// later edits can sync — see [updateLinkedPhoneContact]. If the user declines
/// the permission, it falls back to the permission-free OS "new contact" screen
/// (`openExternalInsert`), which saves the contact but can't be linked for
/// auto-update.
Future<void> saveClientToPhoneContacts(
  BuildContext context,
  WidgetRef ref,
  ClientRecord client,
) async {
  final notices = ref.read(noticeServiceProvider);
  final linkStore = ref.read(contactLinkStoreProvider);
  try {
    final granted = await FlutterContacts.requestPermission();
    if (granted) {
      final inserted = await FlutterContacts.insertContact(
        clientToContact(client),
      );
      await linkStore.link(client.id, inserted.id);
      if (context.mounted) {
        notices.success(context.l10n.clients_savedToContacts);
      }
    } else {
      await FlutterContacts.openExternalInsert(clientToContact(client));
    }
  } catch (_) {
    if (context.mounted) {
      notices.error(context.l10n.error_couldNotOpenContacts);
    }
  }
}

/// Pushes [client]'s current details onto the phone-contact it was previously
/// saved as, if any. Best-effort and silent: a missing link, declined
/// permission, or a deleted contact are all no-ops, and any failure is logged
/// but never surfaced — it must not block or fail the client save.
///
/// Overwrites only the synced fields (name, organization, phones, emails,
/// addresses) on the existing contact, preserving everything else (photo,
/// account, groups).
Future<void> updateLinkedPhoneContact(
  WidgetRef ref,
  ClientRecord client,
) async {
  final linkStore = ref.read(contactLinkStoreProvider);
  final logger = ref.read(loggerProvider);
  // The whole sync is guarded: a missing link, declined permission, or any
  // failure (incl. storage/plugin) must leave the client save untouched.
  try {
    final contactId = await linkStore.contactIdFor(client.id);
    if (contactId == null) return;

    final granted = await FlutterContacts.requestPermission();
    if (!granted) return;

    // withAccounts: updateContact needs the raw account id on Android;
    // properties + photo are fetched by default and must be present or the
    // update would erase them.
    final existing = await FlutterContacts.getContact(
      contactId,
      withAccounts: true,
    );
    if (existing == null) {
      // The user deleted the contact on their phone — drop the stale link.
      await linkStore.unlink(client.id);
      return;
    }

    final mapped = clientToContact(client);
    existing
      ..name = mapped.name
      ..organizations = mapped.organizations
      ..phones = mapped.phones
      ..emails = mapped.emails
      ..addresses = mapped.addresses;
    await FlutterContacts.updateContact(existing);
  } catch (e, st) {
    logger.warn('CLI-CONTACT-SYNC updateLinkedPhoneContact failed', e, st);
  }
}

/// Maps a [ClientRecord] to a flutter_contacts [Contact] for the native insert
/// screen. Pure (no I/O) so it can be unit-tested directly.
///
/// A business name lands on the organization (the OS then displays the contact
/// by company), the person name on the contact name; either may be absent.
/// Empty optional fields are left off so the native form shows blank rows
/// rather than empty entries.
Contact clientToContact(ClientRecord client) {
  final contact = Contact();

  final personName = client.name.trim();
  if (personName.isNotEmpty) {
    contact.name.first = personName;
  }

  final business = client.businessName.trim();
  if (business.isNotEmpty) {
    contact.organizations = [Organization(company: business)];
  }

  final phone = client.phone.trim();
  if (phone.isNotEmpty) {
    contact.phones = [Phone(phone)];
  }

  final email = client.email.trim();
  if (email.isNotEmpty) {
    contact.emails = [Email(email)];
  }

  if (!client.noFixedAddress && client.address.trim().isNotEmpty) {
    final street = AddressParser.canonicalToDisplay(client.address);
    final formatted = [
      street,
      client.city.trim(),
      client.province.trim(),
      client.postalCode.trim(),
      client.country.trim(),
    ].where((part) => part.isNotEmpty).join(', ');

    contact.addresses = [
      Address(
        formatted,
        street: street,
        city: client.city.trim(),
        state: client.province.trim(),
        postalCode: client.postalCode.trim(),
        country: client.country.trim(),
      ),
    ];
  }

  return contact;
}
