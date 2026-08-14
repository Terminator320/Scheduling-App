import 'package:flutter/widgets.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/features/clients/data/contact_link_store.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/domain/policies/client_name_policy.dart';
import 'package:scheduling/features/maps/domain/address_parser.dart';
import 'package:scheduling/l10n/l10n.dart';

/// The contact properties the client sync owns. Updating only these keeps everything
/// else (photo, groups, account) untouched.
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

/// Saves client into device contacts or shows OS new-contact screen if permission denied.
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
  } catch (e, st) {
    // Log this so a contacts-plugin failure still reaches Crashlytics, same as
    // updateLinkedPhoneContact below.
    ref
        .read(loggerProvider)
        .warn('CLI-CONTACT-SAVE saveClientToPhoneContacts failed', e, st);
    if (context.mounted) {
      notices.error(context.l10n.error_couldNotOpenContacts);
    }
  }
}

/// Syncs client details to the phone contact, best-effort and silent. Only overwrites
/// the synced fields.
Future<void> updateLinkedPhoneContact({
  required ContactLinkStore linkStore,
  required AppLogger logger,
  required ClientRecord client,
}) async {
  // Guard the whole sync — any failure here must not affect the client save.
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
        // copyWith keeps the old value when passed null, so we pass an empty Name here
        // to actually clear the contact's name for a name-only client.
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

/// Maps a ClientRecord to a flutter_contacts Contact. The display name goes on the
/// organization field, while first/last name gets its own structured field.
Contact clientToContact(ClientRecord client) {
  // The STORED name carries the client's phone number on the end for Wave's
  // benefit, so it is stripped before it becomes a contact's organization or
  // name — a contacts entry carries the number in its own phone field, and
  // "Vogas Plumbing (514) 555-1234" is not a company.
  final displayName = ClientNamePolicy.stripPhone(
    client.name,
    phone: client.phone,
    mobile: client.mobile,
  );
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
