/// Pure-Dart helpers for splitting an address string into structured
/// pieces and stitching them back together. No Flutter / Firebase imports
/// — exercised directly by `test/features/maps/address_parser_test.dart`.
class AddressParser {
  const AddressParser._();

  /// Splits a raw address into apt + street parts when an apt/unit/suite
  /// marker is detected. Returns `null` if no apt portion is found.
  ///
  /// Recognized shapes (case-insensitive):
  /// 1. `"Apt 12 - 1245 Main St"` (saved canonical form)
  /// 2. `"apt|apartment|unit|suite|ste|# 12, 1245 Main"` (labeled prefix)
  /// 3. `"12 - 1245 Main"` (bare-dash)
  /// 4. `"1245 Rue de Bleury #3406, Montréal, QC"` (trailing unit)
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

  /// Re-formats an address with the apt prefixed in the "12-1245 Main, ..."
  /// canonical form. Strips any embedded "apt/unit/#" tokens already inside
  /// `street` so the apt isn't duplicated when the user edits the field.
  static String combineAptAndStreet(String street, String apt) {
    var cleanStreet = street
        .replaceAll(
          RegExp(
            r'\s+(#|apt\.?|apartment|unit|suite|ste\.?)\s*[-#: ]*\s*[A-Za-z0-9 /]+',
            caseSensitive: false,
          ),
          '',
        )
        .trim();

    final cleanApt = apt.trim().replaceAll(RegExp('^#+'), '');
    if (cleanStreet.isEmpty || cleanApt.isEmpty) return cleanStreet;

    final commaIndex = cleanStreet.indexOf(',');
    if (commaIndex == -1) return '$cleanApt-$cleanStreet';

    final firstLine = cleanStreet.substring(0, commaIndex).trim();
    final rest = cleanStreet.substring(commaIndex);
    return '$cleanApt-$firstLine$rest';
  }

  /// Parses a free-form address string into the structured fields the
  /// client form populates. All fields are nullable — `null` means "no
  /// value extracted, leave the existing controller value alone".
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

/// Apt + street pair returned by `AddressParser.splitApt`.
class AptAddress {
  const AptAddress({required this.apt, required this.street});
  final String apt;
  final String street;
}

/// Inferred pieces of a free-form address. Null means "couldn't extract,
/// leave the caller's existing value alone".
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
