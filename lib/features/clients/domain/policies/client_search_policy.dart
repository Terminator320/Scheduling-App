/// Pure-Dart policy for whether and how a client search query should run.
///
/// Centralizes the rules:
/// * Avoid broad reads for one-letter searches.
/// * Allow short phone-digit searches (≥3 digits).
/// * Server read cap (1000) so we never page the entire collection.
///
/// Lives in `domain/` because it has no Firestore imports — it can be
/// exercised by plain `test()` blocks without a Firebase emulator.
class ClientSearchPolicy {
  const ClientSearchPolicy._();

  static const int minimumTextLength = 2;
  static const int minimumPhoneDigits = 3;
  static const int serverReadLimit = 1000;
  static const int resultDisplayLimit = 25;

  static bool shouldSearch(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return false;
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= minimumPhoneDigits) return true;
    return normalize(trimmed).length >= minimumTextLength;
  }

  static String cacheKey(String query) => normalize(query);

  /// Lower-cases, strips diacritics, and collapses non-alphanumerics.
  /// Public so the repository can reuse the same normalization on document
  /// fields without duplicating the regexes.
  static String normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp('[àáâãäå]'), 'a')
        .replaceAll(RegExp('[èéêë]'), 'e')
        .replaceAll(RegExp('[ìíîï]'), 'i')
        .replaceAll(RegExp('[òóôõö]'), 'o')
        .replaceAll(RegExp('[ùúûü]'), 'u')
        .replaceAll(RegExp('[ç]'), 'c')
        .replaceAll(RegExp('[^a-z0-9]+'), ' ')
        .trim();
  }

  /// Strips everything except `0-9` from a value.
  static String digitsOnly(String value) => value.replaceAll(RegExp(r'\D'), '');
}
