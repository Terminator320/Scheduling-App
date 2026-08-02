class AddressParser {
  const AddressParser._();

  // Compiled once: `canonicalToDisplay` runs per row in the clients list
  // builder, and an address that matches none of these falls through all four.
  static final _savedApt = RegExp(
    r'^Apt-?\s*([^\-]+)\s*-\s*(.+)$',
    caseSensitive: false,
  );
  static final _labeledApt = RegExp(
    r'^\s*(?:apt|apartment|unit|suite|ste|#)\s*[-#: ]*\s*([A-Za-z0-9][A-Za-z0-9 /]*)\s*[-,]\s*(.+)$',
    caseSensitive: false,
  );
  static final _dashApt = RegExp(
    r'^\s*([A-Za-z0-9][A-Za-z0-9 /]*)\s*-\s*(\d+.+)$',
  );
  static final _trailingApt = RegExp(
    r'^\s*(.+?)\s+(?:#|apt\.?|apartment|unit|suite|ste\.?)\s*[-#: ]*\s*([A-Za-z0-9][A-Za-z0-9 /]*)\s*(,.*)?$',
    caseSensitive: false,
  );
  static final _leadingHashes = RegExp('^#+');
  static final _embeddedAptToken = RegExp(
    r'\s+(#|apt\.?|apartment|unit|suite|ste\.?)\s*[-#: ]*\s*[A-Za-z0-9 /]+',
    caseSensitive: false,
  );

  static AptAddress? splitApt(String rawAddress) {
    final value = rawAddress.trim();
    if (value.isEmpty) return null;

    final saved = _savedApt.firstMatch(value);
    if (saved != null) {
      return AptAddress(
        apt: saved.group(1)!.trim(),
        street: saved.group(2)!.trim(),
      );
    }

    final labeled = _labeledApt.firstMatch(value);
    if (labeled != null) {
      return AptAddress(
        apt: labeled.group(1)!.trim(),
        street: labeled.group(2)!.trim(),
      );
    }

    final dash = _dashApt.firstMatch(value);
    if (dash != null) {
      return AptAddress(
        apt: dash.group(1)!.trim(),
        street: dash.group(2)!.trim(),
      );
    }

    final trailing = _trailingApt.firstMatch(value);
    if (trailing != null) {
      final beforeUnit = trailing.group(1)!.trim();
      final apt = trailing.group(2)!.trim();
      final afterUnit = trailing.group(3)?.trim() ?? '';
      return AptAddress(
        apt: apt,
        street: afterUnit.isEmpty ? beforeUnit : '$beforeUnit$afterUnit',
      );
    }

    return null;
  }

  static String combineAptAndStreet(String street, String apt) {
    final cleanStreet = _stripEmbeddedAptToken(street);
    final cleanApt = apt.trim().replaceAll(_leadingHashes, '');
    if (cleanStreet.isEmpty || cleanApt.isEmpty) return cleanStreet;

    final commaIndex = cleanStreet.indexOf(',');
    if (commaIndex == -1) return '$cleanApt-$cleanStreet';

    final firstLine = cleanStreet.substring(0, commaIndex).trim();
    final rest = cleanStreet.substring(commaIndex);
    return '$cleanApt-$firstLine$rest';
  }

  static String formatForDisplay(String street, String apt) {
    final cleanStreet = _stripEmbeddedAptToken(street);
    final cleanApt = apt.trim().replaceAll(_leadingHashes, '');
    if (cleanStreet.isEmpty || cleanApt.isEmpty) return cleanStreet;

    final commaIndex = cleanStreet.indexOf(',');
    if (commaIndex == -1) return '$cleanStreet #$cleanApt';

    final firstLine = cleanStreet.substring(0, commaIndex).trim();
    final rest = cleanStreet.substring(commaIndex);
    return '$firstLine #$cleanApt$rest';
  }

  static String canonicalToDisplay(String stored) {
    final parts = splitApt(stored);
    if (parts == null) return stored;
    return formatForDisplay(parts.street, parts.apt);
  }

  /// The stored form of a street field plus a separate apt field.
  ///
  /// The explicit [apt] wins over an apt embedded in [street]; when it is blank
  /// the embedded one is kept. Both client save paths resolve their address
  /// through here so the precedence rule has exactly one owner.
  static String canonicalFrom({required String street, required String apt}) {
    final parsed = splitApt(street);
    final resolvedStreet = (parsed?.street ?? street).trim();
    final trimmedApt = apt.trim();
    final resolvedApt = trimmedApt.isNotEmpty
        ? trimmedApt
        : (parsed?.apt ?? '').trim();
    return combineAptAndStreet(resolvedStreet, resolvedApt);
  }

  static String toCanonical(String text) {
    final trimmed = text.trim();
    final parts = splitApt(trimmed);
    if (parts == null) return trimmed;
    return combineAptAndStreet(parts.street, parts.apt);
  }

  static String _stripEmbeddedAptToken(String street) {
    return street.replaceAll(_embeddedAptToken, '').trim();
  }

  static ParsedAddressFields parse(String rawAddress) {
    final apt = splitApt(rawAddress);
    final value = (apt?.street ?? rawAddress).trim();
    if (value.isEmpty) {
      return ParsedAddressFields(apt: apt?.apt, street: apt?.street);
    }

    final parts = value
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    final postalMatch = RegExp(
      r'\b[ABCEGHJ-NPRSTVXY]\d[ABCEGHJ-NPRSTV-Z][ -]?\d[ABCEGHJ-NPRSTV-Z]\d\b',
      caseSensitive: false,
    ).firstMatch(value);
    final postalCode = postalMatch?.group(0)?.toUpperCase();

    String? country;
    if (parts.isNotEmpty) {
      final last = parts.last;
      if (postalCode != null &&
          last.toLowerCase().contains(postalCode.toLowerCase())) {
        country = 'Canada';
      } else if (last.length > 2) {
        country = last;
      }
    }

    String? province;
    for (final part in parts) {
      final m = RegExp(
        r'\b(AB|BC|MB|NB|NL|NS|NT|NU|ON|PE|QC|SK|YT)\b',
        caseSensitive: false,
      ).firstMatch(part);
      if (m != null) {
        province = m.group(0)!.toUpperCase();
        break;
      }
    }

    String? city;
    if (parts.length >= 3) {
      final candidate = parts[parts.length - 3];
      if (!RegExp(r'\d').hasMatch(candidate)) city = candidate;
    } else if (parts.length >= 2) {
      final candidate = parts[parts.length - 2];
      if (!RegExp(r'\d').hasMatch(candidate)) city = candidate;
    }

    return ParsedAddressFields(
      apt: apt?.apt,
      street: apt?.street,
      city: city,
      province: province,
      postalCode: postalCode,
      country: country,
    );
  }
}

class AptAddress {
  const AptAddress({required this.apt, required this.street});
  final String apt;
  final String street;
}

class ParsedAddressFields {
  const ParsedAddressFields({
    this.apt,
    this.street,
    this.city,
    this.province,
    this.country,
    this.postalCode,
  });

  final String? apt;
  final String? street;
  final String? city;
  final String? province;
  final String? country;
  final String? postalCode;
}
