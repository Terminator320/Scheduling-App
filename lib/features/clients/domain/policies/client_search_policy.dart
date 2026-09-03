import 'package:scheduling/core/utils/firestore_parsing.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';

/// A pre-normalized searchable projection of a client.
typedef ClientSearchEntry = ({
  ClientRecord client,
  String text,
  String phoneDigits,
});

class ClientSearchPolicy {
  const ClientSearchPolicy._();

  static const int resultDisplayLimit = 25;

  // Compiled once, since digitsOnly runs per row on every keystroke.
  static final _nonDigit = RegExp(r'\D');

  // Kicks in on the first letter or digit — blank or punctuation-only input is
  // ignored so we don't trigger a full collection scan.
  static bool shouldSearch(String query) => normalize(query).isNotEmpty;

  static String cacheKey(String query) => normalize(query);

  /// Lowercase, accent-folded, non-alphanumerics collapsed to single spaces,
  /// trimmed.
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

    // Latin-1 accents, upper and lower, folded to their bare letter.
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

  /// [index] + [entryMatches] in one call, for a caller holding a single client
  /// and no projection.
  static bool matchesClient(ClientRecord client, String query) {
    final q = normalize(query);
    final qDigits = digitsOnly(query);
    if (q.isEmpty && qDigits.isEmpty) return false;
    return entryMatches(index(client), queryText: q, queryDigits: qDigits);
  }

  /// Normalizes one client into a [ClientSearchEntry].
  static ClientSearchEntry index(ClientRecord client) => (
    client: client,
    text: normalize(
      [
        client.name,
        // Legacy pre-Wave-reshape docs kept the business under its own field.
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
  static int relevanceScore({
    required String displayName,
    required String personName,
    required String phoneDigits,
    required String contactsDigits,
    required String queryText,
    required String queryDigits,
  }) {
    if (displayName == queryText || phoneDigits == queryDigits) return 0;
    if (displayName.startsWith(queryText) || personName.startsWith(queryText)) {
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
