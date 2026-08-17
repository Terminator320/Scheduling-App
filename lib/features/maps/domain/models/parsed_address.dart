import 'package:freezed_annotation/freezed_annotation.dart';

part 'parsed_address.freezed.dart';

/// A Places result, as returned by `placesGetDetails`.
///
/// Only [fullAddress] is read today — `AddressAutocompleteField` formats that
/// one string and hands it to the form. The four components are kept
/// deliberately rather than trimmed: they are parsed server-side from the
/// `addressComponents` field mask that `functions/places.js` already requests,
/// and they are what a structured address entry would need. Kept, not dead —
/// don't wire a caller to them without deciding whether the form should hold
/// components instead of one line.
@freezed
abstract class ParsedAddress with _$ParsedAddress {
  const factory ParsedAddress({
    @Default('') String fullAddress,
    @Default('') String street,
    @Default('') String city,
    @Default('') String province,
    @Default('') String postalCode,
  }) = _ParsedAddress;
  const ParsedAddress._();

  factory ParsedAddress.fromMap(Map<String, dynamic> map) => ParsedAddress(
    fullAddress: (map['fullAddress'] as String?) ?? '',
    street: (map['street'] as String?) ?? '',
    city: (map['city'] as String?) ?? '',
    province: (map['province'] as String?) ?? '',
    postalCode: (map['postalCode'] as String?) ?? '',
  );

  Map<String, dynamic> toMap() => {
    'fullAddress': fullAddress,
    'street': street,
    'city': city,
    'province': province,
    'postalCode': postalCode,
  };
}
