class ClientSearchPolicy {
  const ClientSearchPolicy._();

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
}
