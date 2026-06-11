import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local link between a client and the phone-contact it was saved as,
/// so a later client edit can update that same contact.
///
/// The native contact id is local to this device, so the link only exists where
/// the contact was saved — a reinstall or a second device starts with no links.
/// Non-sensitive (just a contact id), so it lives in `SharedPreferences` rather
/// than secure storage.
class ContactLinkStore {
  const ContactLinkStore();

  static const _prefix = 'contact_link_';

  /// The native contact id previously saved for [clientId], or null if this
  /// client has never been saved to contacts on this device.
  Future<String?> contactIdFor(String clientId) async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('$_prefix$clientId');
    return (id == null || id.isEmpty) ? null : id;
  }

  Future<void> link(String clientId, String contactId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$clientId', contactId);
  }

  Future<void> unlink(String clientId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$clientId');
  }
}

final contactLinkStoreProvider = Provider<ContactLinkStore>(
  (ref) => const ContactLinkStore(),
);
