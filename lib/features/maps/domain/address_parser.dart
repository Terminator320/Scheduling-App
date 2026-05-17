class AddressParser {
  const AddressParser._();

  static AptAddress? splitApt(String rawAddress) {
    final value = rawAddress.trim();
    if (value.isEmpty) return null;

    final saved = RegExp(
      r'^Apt-?\s*([^\-]+)\s*-\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(value);
    if (saved != null) {
      return AptAddress(
        apt: saved.group(1)!.trim(),
        street: saved.group(2)!.trim(),
      );
    }

    final labeled = RegExp(
      r'^\s*(?:apt|apartment|unit|suite|ste|#)\s*[-#: ]*\s*([A-Za-z0-9][A-Za-z0-9 /]*)\s*[-,]\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(value);
    if (labeled != null) {
      return AptAddress(
        apt: labeled.group(1)!.trim(),
        street: labeled.group(2)!.trim(),
      );
    }

    final dash = RegExp(
      r'^\s*([A-Za-z0-9][A-Za-z0-9 /]*)\s*-\s*(\d+.+)$',
    ).firstMatch(value);
    if (dash != null) {
      return AptAddress(
        apt: dash.group(1)!.trim(),
        street: dash.group(2)!.trim(),
      );
    }

    final trailing = RegExp(
      r'^\s*(.+?)\s+(?:#|apt\.?|apartment|unit|suite|ste\.?)\s*[-#: ]*\s*([A-Za-z0-9][A-Za-z0-9 /]*)\s*(,.*)?$',
      caseSensitive: false,
    ).firstMatch(value);
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
    final cleanApt = apt.trim().replaceAll(RegExp('^#+'), '');
    if (cleanStreet.isEmpty || cleanApt.isEmpty) return cleanStreet;

    final commaIndex = cleanStreet.indexOf(',');
    if (commaIndex == -1) return '$cleanApt-$cleanStreet';

    final firstLine = cleanStreet.substring(0, commaIndex).trim();
    final rest = cleanStreet.substring(commaIndex);
    return '$cleanApt-$firstLine$rest';
  }

  static String formatForDisplay(String street, String apt) {
    final cleanStreet = _stripEmbeddedAptToken(street);
    final cleanApt = apt.trim().replaceAll(RegExp('^#+'), '');
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

  static String toCanonical(String text) {
    final trimmed = text.trim();
    final parts = splitApt(trimmed);
    if (parts == null) return trimmed;
    return combineAptAndStreet(parts.street, parts.apt);
  }

  static String _stripEmbeddedAptToken(String street) {
    return street
        .replaceAll(
          RegExp(
            r'\s+(#|apt\.?|apartment|unit|suite|ste\.?)\s*[-#: ]*\s*[A-Za-z0-9 /]+',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
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
