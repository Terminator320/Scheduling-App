import 'package:flutter/widgets.dart';

import 'package:scheduling/features/maps/domain/address_parser.dart';

/// Parses [rawAddress] and copies each recognized part into the matching
/// controller.
///
/// **Most fields are OVERWRITTEN, and that is the intent** — this runs when the
/// user picks an address, so `city`, `province` and `postalCode` take the
/// picked value outright. Filling those in is the whole reason the lookup
/// exists, and leaving a stale city beside a new street would be worse than
/// wrong: it would be wrong and invisible.
///
/// Three fields are deliberate exceptions, each for its own reason:
///
/// - **`apt`** fills only when empty. A unit number is the one part of an
///   address a suggestion never knows and the user always does, so a typed
///   value must win.
/// - **`street`** is skipped when it already equals the parsed value, so the
///   caret isn't yanked to the end of a field the user may still be editing.
/// - **`country`** keeps an existing value against a parsed `Canada`, which is
///   what the parser falls back to when it recognizes nothing better.
///
/// (This docstring used to claim it left "manually-entered values intact",
/// which described none of the three rules and contradicted the other three
/// fields entirely.)
void fillAddressControllersFromText(
  String rawAddress, {
  required TextEditingController address,
  required TextEditingController apt,
  required TextEditingController city,
  required TextEditingController province,
  required TextEditingController postalCode,
  required TextEditingController country,
}) {
  final fields = AddressParser.parse(rawAddress);

  if (fields.apt != null && apt.text.trim().isEmpty) {
    apt.text = fields.apt!;
  }
  if (fields.street != null && address.text.trim() != fields.street) {
    address.value = TextEditingValue(
      text: fields.street!,
      selection: TextSelection.collapsed(offset: fields.street!.length),
    );
  }
  if (fields.postalCode != null) {
    postalCode.text = fields.postalCode!;
  }
  if (fields.country != null &&
      (fields.country != 'Canada' || country.text.trim().isEmpty)) {
    country.text = fields.country!;
  }
  if (fields.province != null) province.text = fields.province!;
  if (fields.city != null) city.text = fields.city!;
}
