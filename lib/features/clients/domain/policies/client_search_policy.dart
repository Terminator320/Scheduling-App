class ClientSearchPolicy {
  const ClientSearchPolicy._();

  static const int minimumTextLength = 2;
  static const int minimumPhoneDigits = 3;
  static const int serverReadLimit = 1000;
  static const int resultDisplayLimit = 25;

  // Compiled once — normalize/digitsOnly run per row per keystroke in the
  // client-side search paths.
  static final _accentA = RegExp('[àáâãäå]');
  static final _accentE = RegExp('[èéêë]');
  static final _accentI = RegExp('[ìíîï]');
  static final _accentO = RegExp('[òóôõö]');
  static final _accentU = RegExp('[ùúûü]');
  static final _accentC = RegExp('[ç]');
  static final _nonAlphanumeric = RegExp('[^a-z0-9]+');
  static final _nonDigit = RegExp(r'\D');

  static bool shouldSearch(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return false;
    if (digitsOnly(trimmed).length >= minimumPhoneDigits) return true;
    return normalize(trimmed).length >= minimumTextLength;
  }

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
}
