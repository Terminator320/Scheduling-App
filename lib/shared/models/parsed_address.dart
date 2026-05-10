class ParsedAddress {
  final String fullAddress;
  final String street;
  final String city;
  final String province;
  final String postalCode;

  ParsedAddress({
    required this.fullAddress,
    required this.street,
    required this.city,
    required this.province,
    required this.postalCode,
  });

  Map<String, dynamic> toMap() {
    return {
      'fullAddress': fullAddress,
      'street': street,
      'city': city,
      'province': province,
      'postalCode': postalCode,
    };
  }

  factory ParsedAddress.fromMap(Map<String, dynamic> map) {
    return ParsedAddress(
      fullAddress: (map['fullAddress'] as String?) ?? '',
      street: (map['street'] as String?) ?? '',
      city: (map['city'] as String?) ?? '',
      province: (map['province'] as String?) ?? '',
      postalCode: (map['postalCode'] as String?) ?? '',
    );
  }
}
