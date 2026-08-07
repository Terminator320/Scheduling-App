import 'package:flutter/widgets.dart';

import 'package:scheduling/features/maps/domain/address_parser.dart';

/// Parses [rawAddress] and copies each recognized part into the matching controller, leaving manually-entered values intact.
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
