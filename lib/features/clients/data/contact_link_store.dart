import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local link between client and phone-contact for later edits; non-sensitive SharedPreferences.
class ContactLinkStore {
  const ContactLinkStore();

  static const _prefix = 'contact_link_';

  /// Native contact id for [clientId] if saved on this device, or null.
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
