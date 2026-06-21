import 'package:flutter/widgets.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/features/clients/data/contact_link_store.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/maps/domain/address_parser.dart';
import 'package:scheduling/l10n/l10n.dart';

/// The contact properties the client sync owns. Fetching exactly this set
/// before `update` means only these are overwritten — everything else
/// (photo, groups, account) is untouched by design of the 2.x API.
const Set<ContactProperty> _syncedProperties = {
  ContactProperty.name,
  ContactProperty.organization,
  ContactProperty.phone,
  ContactProperty.email,
  ContactProperty.address,
};

Future<bool> _requestContactsPermission() async {
  final status = await FlutterContacts.permissions.request(
    PermissionType.readWrite,
  );
  return status == PermissionStatus.granted ||
      status == PermissionStatus.limited;
}

/// Saves [client] into the device's contacts.
///
/// With the Contacts permission granted, the contact is written directly and
/// the resulting native id is linked to the client (via [ContactLinkStore]) so
/// later edits can sync — see [updateLinkedPhoneContact]. If the user declines
/// the permission, it falls back to the permission-free OS "new contact"
/// screen (`showCreator`), which also links when the user saves (the id is
/// null if they cancel).
Future<void> saveClientToPhoneContacts(
  BuildContext context,
  WidgetRef ref,
  ClientRecord client,
) async {
  final notices = ref.read(noticeServiceProvider);
  final linkStore = ref.read(contactLinkStoreProvider);
  try {
    if (await _requestContactsPermission()) {
      final insertedId = await FlutterContacts.create(clientToContact(client));
      await linkStore.link(client.id, insertedId);
      if (context.mounted) {
        notices.success(context.l10n.clients_savedToContacts);
      }
    } else {
      final createdId = await FlutterContacts.native.showCreator(
        contact: clientToContact(client),
      );
      if (createdId != null) {
        await linkStore.link(client.id, createdId);
      }
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
/// addresses); unfetched properties (photo, groups, account) are preserved
/// because `update` only writes the properties that were fetched.
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

    if (!await _requestContactsPermission()) return;

    final existing = await FlutterContacts.get(
      contactId,
      properties: _syncedProperties,
    );
    if (existing == null) {
      // The user deleted the contact on their phone — drop the stale link.
      await linkStore.unlink(client.id);
      return;
    }

    final mapped = clientToContact(client);
    await FlutterContacts.update(
      existing.copyWith(
        // copyWith keeps the old value on null — pass an empty Name so a
        // client without a person name clears the contact's, as before.
        name: mapped.name ?? const Name(),
        organizations: mapped.organizations,
        phones: mapped.phones,
        emails: mapped.emails,
        addresses: mapped.addresses,
      ),
    );
  } catch (e, st) {
    logger.warn('CLI-CONTACT-SYNC updateLinkedPhoneContact failed', e, st);
  }
}

/// Maps a [ClientRecord] to a flutter_contacts [Contact] for the native insert
/// screen. Pure (no I/O) so it can be unit-tested directly.
///
/// The structured person name comes from `firstName`/`lastName`; `name` (the
/// customer/display name) lands on the organization so the OS shows the contact
/// by that name, and — when there is no first/last name — also seeds the
/// contact's name (so a name-only client isn't a blank contact). `phone` and
/// `mobile` map to two separate phone entries. Empty optional fields are left
/// off so the native form shows blank rows rather than empty entries.
Contact clientToContact(ClientRecord client) {
  final displayName = client.name.trim();
  final first = client.firstName.trim();
  final last = client.lastName.trim();
  final phone = client.phone.trim();
  final mobile = client.mobile.trim();
  final email = client.email.trim();

  // Prefer the structured first/last name; fall back to the display name so a
  // name-only client still gets a contact name.
  final Name? name;
  if (first.isNotEmpty || last.isNotEmpty) {
    name = Name(first: first, last: last);
  } else if (displayName.isNotEmpty) {
    name = Name(first: displayName);
  } else {
    name = null;
  }

  Address? address;
  if (!client.noFixedAddress && client.address.trim().isNotEmpty) {
    final street = AddressParser.canonicalToDisplay(client.address);
    final formatted = [
      street,
      client.city.trim(),
      client.province.trim(),
      client.postalCode.trim(),
      client.country.trim(),
    ].where((part) => part.isNotEmpty).join(', ');

    address = Address(
      formatted: formatted,
      street: street,
      city: client.city.trim(),
      state: client.province.trim(),
      postalCode: client.postalCode.trim(),
      country: client.country.trim(),
    );
  }

  return Contact(
    name: name,
    organizations: [
      if (displayName.isNotEmpty) Organization(name: displayName),
    ],
    phones: [
      if (phone.isNotEmpty)
        Phone(number: phone, label: const Label(PhoneLabel.work)),
      if (mobile.isNotEmpty)
        Phone(number: mobile, label: const Label(PhoneLabel.mobile)),
    ],
    emails: [if (email.isNotEmpty) Email(address: email)],
    addresses: [?address],
  );
}
