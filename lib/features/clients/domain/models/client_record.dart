import 'package:freezed_annotation/freezed_annotation.dart';

part 'client_record.freezed.dart';

/// Firestore collection: `clients`
///
/// Example doc shape:
/// ```json
/// {
///   "businessName": "Acme Inc",
///   "name": "Jane Doe",
///   "address": "12-1245 Rue de Bleury, Montréal, QC",
///   "apt": "12",
///   "city": "Montréal",
///   "province": "QC",
///   "country": "Canada",
///   "postalCode": "H3B 0A8",
///   "phone": "+1-514-555-0101",
///   "email": "jane@acme.com",
///   "contacts": [
///     { "name": "Bob", "phone": "+1-514-555-0102", "email": "bob@acme.com" }
///   ],
///   "createdAt": Timestamp,
///   "updatedAt": Timestamp
/// }
/// ```
@freezed
abstract class ClientContact with _$ClientContact {
  const ClientContact._();

  const factory ClientContact({
    @Default('') String name,
    @Default('') String phone,
    @Default('') String email,
  }) = _ClientContact;

  factory ClientContact.fromMap(Map<String, dynamic> map) {
    return ClientContact(
      name: (map['name'] ?? '').toString(),
      phone: (map['phone'] ?? '').toString(),
      email: (map['email'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name.trim(),
    'phone': phone.trim(),
    'email': email.trim(),
  };
}

@freezed
abstract class ClientRecord with _$ClientRecord {
  const ClientRecord._();

  const factory ClientRecord({
    required String id,
    @Default('') String businessName,
    @Default('') String name,
    @Default('') String address,
    @Default('') String apt,
    @Default('') String city,
    @Default('') String province,
    @Default('') String country,
    @Default('') String postalCode,
    @Default('') String phone,
    @Default('') String email,
    @Default(<ClientContact>[]) List<ClientContact> contacts,
  }) = _ClientRecord;

  factory ClientRecord.fromMap(String id, Map<String, dynamic> data) {
    final rawContacts = (data['contacts'] as List?) ?? const [];
    return ClientRecord(
      id: id,
      businessName: (data['businessName'] ?? '').toString(),
      name: (data['name'] ?? '').toString(),
      address: (data['address'] ?? '').toString(),
      apt: (data['apt'] ?? '').toString(),
      city: (data['city'] ?? '').toString(),
      province: (data['province'] ?? '').toString(),
      country: (data['country'] ?? '').toString(),
      postalCode: (data['postalCode'] ?? '').toString(),
      phone: (data['phone'] ?? '').toString(),
      email: (data['email'] ?? '').toString(),
      contacts: rawContacts
          .whereType<Map>()
          .map((c) => ClientContact.fromMap(Map<String, dynamic>.from(c)))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() => {
    'businessName': businessName.trim(),
    'name': name.trim(),
    'address': address.trim(),
    'apt': apt.trim(),
    'city': city.trim(),
    'province': province.trim(),
    'country': country.trim(),
    'postalCode': postalCode.trim(),
    'phone': phone.trim(),
    'email': email.trim(),
    'contacts': contacts.map((c) => c.toMap()).toList(),
  };

  String get displayName => businessName.isNotEmpty ? businessName : name;

  List<ClientContact> get displayContact => contacts;
}
