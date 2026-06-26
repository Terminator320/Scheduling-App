import 'package:scheduling/features/clients/domain/models/client_record.dart';

class ClientSearchPolicy {
  const ClientSearchPolicy._();

  static const int serverReadLimit = 1000;
  static const int resultDisplayLimit = 25;

  // Compiled once; normalize/digitsOnly run per row per keystroke in the
  // client-side search paths.
  static final _accentA = RegExp('[\u00E0\u00E1\u00E2\u00E3\u00E4\u00E5]');
  static final _accentE = RegExp('[\u00E8\u00E9\u00EA\u00EB]');
  static final _accentI = RegExp('[\u00EC\u00ED\u00EE\u00EF]');
  static final _accentO = RegExp('[\u00F2\u00F3\u00F4\u00F5\u00F6]');
  static final _accentU = RegExp('[\u00F9\u00FA\u00FB\u00FC]');
  static final _accentC = RegExp('[\u00E7]');
  static final _nonAlphanumeric = RegExp('[^a-z0-9]+');
  static final _nonDigit = RegExp(r'\D');

  // Search starts from the first searchable character: any single letter or
  // digit triggers it (normalize keeps a-z0-9). Blank or punctuation-only
  // input is ignored so an empty/symbol-only query never scans the collection.
  static bool shouldSearch(String query) => normalize(query).isNotEmpty;

  static String cacheKey(String query) => normalize(query);

  static String normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(_accentA, 'a')
        .replaceAll(_accentE, 'e')
        .replaceAll(_accentI, 'i')
        .replaceAll(_accentO, 'o')
        .replaceAll(_accentU, 'u')
        .replaceAll(_accentC, 'c')
        .replaceAll(_nonAlphanumeric, ' ')
        .trim();
  }

  static String digitsOnly(String value) => value.replaceAll(_nonDigit, '');

  // Client-side fallback matcher used by the clients list for instant results
  // while the comprehensive server-backed search loads. Matches the same fields
  // the server search indexes, as far as a loaded ClientRecord exposes them
  // (accent-folded text + digits-only phone). Single source of truth so the
  // list view and its test can't drift.
  static bool matchesClient(ClientRecord client, String query) {
    final q = normalize(query);
    final qDigits = digitsOnly(query);
    if (q.isEmpty && qDigits.isEmpty) return false;

    final text = normalize(
      [
        client.name,
        client.firstName,
        client.lastName,
        client.email,
        client.address,
        client.city,
        client.province,
        client.postalCode,
        client.country,
        for (final c in client.contacts) '${c.name} ${c.email}',
      ].join(' '),
    );
    final phoneDigits = digitsOnly(
      [
        client.phone,
        client.mobile,
        for (final c in client.contacts) c.phone,
      ].join(' '),
    );

    final matchesText = q.isNotEmpty && text.contains(q);
    final matchesPhone = qDigits.isNotEmpty && phoneDigits.contains(qDigits);
    return matchesText || matchesPhone;
  }
}
