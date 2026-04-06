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
      fullAddress: map['fullAddress'] ?? '',
      street: map['street'] ?? '',
      city: map['city'] ?? '',
      province: map['province'] ?? '',
      postalCode: map['postalCode'] ?? '',
    );
  }
}
