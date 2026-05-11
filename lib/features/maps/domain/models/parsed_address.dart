import 'package:freezed_annotation/freezed_annotation.dart';

part 'parsed_address.freezed.dart';

/// Structured address parsed from a Google Places `places.get` response.
/// Stored on `ClientRecord` as nested fields.
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
