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

  static String digitsOnly(String value) => value.replaceAll(RegExp(r'\D'), '');
}
