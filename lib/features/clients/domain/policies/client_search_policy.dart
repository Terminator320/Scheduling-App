import 'package:scheduling/core/utils/firestore_parsing.dart';
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

  static const int resultDisplayLimit = 25;

  // Compiled once, since digitsOnly runs per row on every keystroke. The six
  // accent classes and the `[^a-z0-9]+` collapse that used to sit beside it
  // are now folded into `_foldAccent`'s single pass; see `normalize`.
  static final _nonDigit = RegExp(r'\D');

  // Kicks in on the first letter or digit — blank or punctuation-only input is ignored
  // so we don't trigger a full collection scan.
  static bool shouldSearch(String query) => normalize(query).isNotEmpty;

  static String cacheKey(String query) => normalize(query);

  /// Lowercase, accent-folded, non-alphanumerics collapsed to single spaces,
  /// trimmed.
  ///
  /// One pass over the code units rather than a chain of `replaceAll`s. It ran
  /// per document over a scan window of thousands, and each link in the chain
  /// scanned the whole string and allocated a new one — nine passes and nine
  /// intermediate strings for every row, on the order of 10⁷ character copies
  /// per search. The regexes above are kept because [digitsOnly] and the
  /// callers of [_foldAccent] below still read as the same rules.
  static String normalize(String value) {
    final out = StringBuffer();
    var pendingSpace = false;
    for (var i = 0; i < value.length; i++) {
      final folded = _foldAccent(value.codeUnitAt(i));
      if (folded == null) {
        // Any run of non-alphanumerics becomes at most one space, and a
        // trailing run never emits — that is `replaceAll(...)` + `trim()`.
        pendingSpace = out.isNotEmpty;
        continue;
      }
      if (pendingSpace) {
        out.writeCharCode(0x20);
        pendingSpace = false;
      }
      out.writeCharCode(folded);
    }
    return out.toString();
  }

  /// The lowercased, accent-folded `a-z0-9` code unit for [unit], or null when
  /// it is not alphanumeric at all.
  static int? _foldAccent(int unit) {
    // ASCII fast path: digits, then upper- and lower-case letters.
    if (unit >= 0x30 && unit <= 0x39) return unit;
    if (unit >= 0x41 && unit <= 0x5A) return unit + 0x20;
    if (unit >= 0x61 && unit <= 0x7A) return unit;

    // Latin-1 accents, upper and lower, folded to their bare letter. Mirrors
    // the six `_accent*` classes: toLowerCase() ran first there, so the
    // upper-case ranges fold to the same letters.
    return switch (unit) {
      >= 0x00C0 && <= 0x00C5 => 0x61, // À-Å
      >= 0x00E0 && <= 0x00E5 => 0x61, // à-å
      0x00C7 || 0x00E7 => 0x63, // Ç ç
      >= 0x00C8 && <= 0x00CB => 0x65, // È-Ë
      >= 0x00E8 && <= 0x00EB => 0x65, // è-ë
      >= 0x00CC && <= 0x00CF => 0x69, // Ì-Ï
      >= 0x00EC && <= 0x00EF => 0x69, // ì-ï
      >= 0x00D2 && <= 0x00D6 => 0x6F, // Ò-Ö
      >= 0x00F2 && <= 0x00F6 => 0x6F, // ò-ö
      >= 0x00D9 && <= 0x00DC => 0x75, // Ù-Ü
      >= 0x00F9 && <= 0x00FC => 0x75, // ù-ü
      _ => null,
    };
  }

  static String digitsOnly(String value) => value.replaceAll(_nonDigit, '');

  /// [index] + [entryMatches] in one call, for a caller holding a single
  /// client and no projection.
  ///
  /// **NOT the hot path, and not what new matching should route through.** The
  /// split exists FOR performance: `index` is hoisted to run once per data
  /// change, while this rebuilds the projection per candidate per keystroke —
  /// so every production path uses `index()` + `entryMatches()` (the loaded-page
  /// filter) or `rawMatches()` (the debounced server scan). It has no
  /// production caller at all; it survives because a one-client assertion reads
  /// better in a test than a two-step one.
  ///
  /// The field set still has exactly one owner — this delegates rather than
  /// re-spelling it — so it cannot drift from the matchers above. CLAUDE.md
  /// used to name THIS as "the single client-side fallback matcher, route new
  /// client matching through it", which pointed an author straight at the
  /// function the hot paths were refactored to avoid.
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

  /// [entryMatches] against a RAW Firestore map, without building a
  /// [ClientRecord] first.
  ///
  /// The scan window is thousands of documents and a committed search keeps
  /// [resultDisplayLimit], so building a record per candidate is paid ~200×
  /// over for nothing — the same reasoning the history matcher already
  /// follows. It lives beside [index] because the two MUST agree on the field
  /// set: a spelling that read less would silently stop finding clients the
  /// record itself would have matched, with nothing logged.
  ///
  /// Joining raw `name` and `businessName` reproduces `fromMap`'s fallback for
  /// matching purposes — when `name` is blank the fallback contributes
  /// `businessName`, which is in the blob either way — so no legacy doc goes
  /// invisible here.
  static bool rawMatches(
    Map<String, dynamic> data, {
    required String queryText,
    required String queryDigits,
  }) {
    if (queryText.isEmpty && queryDigits.isEmpty) return false;
    final contacts = firestoreList(data['contacts']);

    if (queryText.isNotEmpty) {
      final text = normalize(
        [
          data['name'] ?? '',
          data['businessName'] ?? '',
          data['firstName'] ?? '',
          data['lastName'] ?? '',
          data['email'] ?? '',
          data['address'] ?? '',
          data['city'] ?? '',
          data['province'] ?? '',
          data['postalCode'] ?? '',
          data['country'] ?? '',
          for (final c in contacts.whereType<Map<Object?, Object?>>())
            '${c['name'] ?? ''} ${c['email'] ?? ''}',
        ].join(' '),
      );
      if (text.contains(queryText)) return true;
    }

    if (queryDigits.isNotEmpty) {
      final phoneDigits = digitsOnly(
        [
          data['phone'] ?? '',
          data['mobile'] ?? '',
          for (final c in contacts.whereType<Map<Object?, Object?>>())
            c['phone'] ?? '',
        ].join(' '),
      );
      if (phoneDigits.contains(queryDigits)) return true;
    }

    return false;
  }

  /// How well a client matches a query — LOWER is better, 0 is exact.
  ///
  /// Product behaviour, not storage: this ranks what the user sees, and it sat
  /// inside `matchClientDocs` in the data layer while its own match half
  /// ([rawMatches]) already lived here. The two are one decision about what
  /// "matching" means, so they belong in one file.
  ///
  /// The six tiers, in order:
  ///   0 — the whole display name or the whole phone, exactly
  ///   1 — display name or person name STARTS with the query
  ///   2 — phone starts with the query's digits
  ///   3 — display name or person name CONTAINS it
  ///   4 — the client's or a contact's phone contains it
  ///   5 — matched on something else (address, email, a contact's name)
  ///
  /// A prefix outranks a substring on purpose: someone typing "tre" wants
  /// Tremblay above Latreille. Phone tiers sit BELOW their name equivalents
  /// because a digit run is the more accidental match of the two — but an
  /// exact phone ties with an exact name at 0, since nobody types ten digits
  /// by accident.
  ///
  /// [displayName], [personName] and both digit strings must already be
  /// normalized through [normalize] / [digitsOnly]; the caller has them in
  /// hand from the match pass, and re-normalizing here would pay for the most
  /// expensive part of this search a second time.
  static int relevanceScore({
    required String displayName,
    required String personName,
    required String phoneDigits,
    required String contactsDigits,
    required String queryText,
    required String queryDigits,
  }) {
    if (displayName == queryText || phoneDigits == queryDigits) return 0;
    if (displayName.startsWith(queryText) ||
        personName.startsWith(queryText)) {
      return 1;
    }
    if (queryDigits.isNotEmpty && phoneDigits.startsWith(queryDigits)) return 2;
    if (displayName.contains(queryText) || personName.contains(queryText)) {
      return 3;
    }
    if (queryDigits.isNotEmpty &&
        (phoneDigits.contains(queryDigits) ||
            contactsDigits.contains(queryDigits))) {
      return 4;
    }
    return 5;
  }

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
