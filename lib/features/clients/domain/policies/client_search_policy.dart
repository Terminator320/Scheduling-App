import 'package:scheduling/features/clients/domain/models/client_record.dart';

/// A pre-normalized searchable projection of a client. We build this once per data
/// change so filtering on every keystroke stays cheap.
typedef ClientSearchEntry = ({
  ClientRecord client,
  String text,
  String phoneDigits,
});

class ClientSearchPolicy {
  const ClientSearchPolicy._();

  static const int serverReadLimit = 1000;
  static const int resultDisplayLimit = 25;

  /// How long a search field waits after the last keystroke before it reads.
  ///
  /// One owner because it is one cost dial, not a per-surface taste: every
  /// debounced search in the app spends the same bounded [serverReadLimit]
  /// window on the same collections. It was written out at four call sites and
  /// had already split two ways (300 ms on the two appointment sheets, 250 ms
  /// on Clients and History), which is the drift this constant ends.
  static const Duration searchDebounce = Duration(milliseconds: 250);

  // These are compiled once, since normalize/digitsOnly run per row on every keystroke.
  static final _accentA = RegExp('[\u00E0\u00E1\u00E2\u00E3\u00E4\u00E5]');
  static final _accentE = RegExp('[\u00E8\u00E9\u00EA\u00EB]');
  static final _accentI = RegExp('[\u00EC\u00ED\u00EE\u00EF]');
  static final _accentO = RegExp('[\u00F2\u00F3\u00F4\u00F5\u00F6]');
  static final _accentU = RegExp('[\u00F9\u00FA\u00FB\u00FC]');
  static final _accentC = RegExp('[\u00E7]');
  static final _nonAlphanumeric = RegExp('[^a-z0-9]+');
  static final _nonDigit = RegExp(r'\D');

  // Kicks in on the first letter or digit — blank or punctuation-only input is ignored
  // so we don't trigger a full collection scan.
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

  // Client-side fallback matcher used for instant results — this is the single source
  // of truth for matching on these fields.
  static bool matchesClient(ClientRecord client, String query) {
    final q = normalize(query);
    final qDigits = digitsOnly(query);
    if (q.isEmpty && qDigits.isEmpty) return false;
    return entryMatches(index(client), queryText: q, queryDigits: qDigits);
  }

  /// Normalizes one client into a [ClientSearchEntry]. Hoisted out so this runs once
  /// per data change instead of once per keystroke.
  static ClientSearchEntry index(ClientRecord client) => (
    client: client,
    text: normalize(
      [
        client.name,
        // Legacy pre-Wave-reshape docs kept the business under its own field.
        // `name` only falls back to it when blank, so a doc carrying both needs
        // this to stay findable by the business name.
        client.businessName,
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
    ),
    phoneDigits: digitsOnly(
      [
        client.phone,
        client.mobile,
        for (final c in client.contacts) c.phone,
      ].join(' '),
    ),
  );

  /// The cheap half of [matchesClient] — just two substring checks against an
  /// already-normalized entry and query.
  static bool entryMatches(
    ClientSearchEntry entry, {
    required String queryText,
    required String queryDigits,
  }) {
    final matchesText = queryText.isNotEmpty && entry.text.contains(queryText);
    final matchesPhone =
        queryDigits.isNotEmpty && entry.phoneDigits.contains(queryDigits);
    return matchesText || matchesPhone;
  }
}
