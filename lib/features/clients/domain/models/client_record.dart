import 'package:freezed_annotation/freezed_annotation.dart';

part 'client_record.freezed.dart';

@freezed
abstract class ClientContact with _$ClientContact {
  const factory ClientContact({
    @Default('') String name,
    @Default('') String phone,
    @Default('') String email,
  }) = _ClientContact;
  const ClientContact._();

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
  const factory ClientRecord({
    required String id,
    @Default('') String name,
    @Default('') String firstName,
    @Default('') String lastName,
    @Default('') String address,
    @Default('') String apt,
    @Default('') String city,
    @Default('') String province,
    @Default('') String country,
    @Default('') String postalCode,
    @Default('') String phone,
    @Default('') String mobile,
    @Default('') String email,
    @Default(<ClientContact>[]) List<ClientContact> contacts,
    @Default(false) bool noFixedAddress,
    // Wave projection (read-only): written exclusively by Cloud Functions via
    // the Admin SDK. The app reads them for a sync indicator and MUST NOT emit
    // them in toMap — firestore.rules rejects any client write that touches
    // `waveCustomerId` or `wave`.
    @Default(null) String? waveCustomerId,
    @Default('') String waveSyncState,
    @Default(null) String? waveSyncError,
  }) = _ClientRecord;
  const ClientRecord._();

  factory ClientRecord.fromMap(String id, Map<String, dynamic> data) {
    final rawContacts = (data['contacts'] as List?) ?? const [];
    final wave = (data['wave'] as Map?)?.cast<String, dynamic>();
    // Back-compat: pre-Wave-reshape docs stored a business-type client as
    // `businessName` with an empty `name`. Fall back so those docs keep a
    // display name and stay editable/searchable until a backfill runs.
    final rawName = (data['name'] ?? '').toString();
    final name = rawName.trim().isNotEmpty
        ? rawName
        : (data['businessName'] ?? '').toString();
    return ClientRecord(
      id: id,
      name: name,
      firstName: (data['firstName'] ?? '').toString(),
      lastName: (data['lastName'] ?? '').toString(),
      address: (data['address'] ?? '').toString(),
      apt: (data['apt'] ?? '').toString(),
      city: (data['city'] ?? '').toString(),
      province: (data['province'] ?? '').toString(),
      country: (data['country'] ?? '').toString(),
      postalCode: (data['postalCode'] ?? '').toString(),
      phone: (data['phone'] ?? '').toString(),
      mobile: (data['mobile'] ?? '').toString(),
      email: (data['email'] ?? '').toString(),
      contacts: rawContacts
          .whereType<Map<Object?, Object?>>()
          .map((c) => ClientContact.fromMap(Map<String, dynamic>.from(c)))
          .toList(),
      noFixedAddress: (data['noFixedAddress'] as bool?) ?? false,
      waveCustomerId: data['waveCustomerId']?.toString(),
      waveSyncState: (wave?['syncState'] ?? '').toString(),
      waveSyncError: wave?['syncError']?.toString(),
    );
  }

  /// Only the user-owned fields. Deliberately omits `waveCustomerId` and the
  /// `wave` sub-map: those are function-owned, and the `clients` update rule
  /// rejects any write that adds/changes them (`updateClient` uses `.update`).
  Map<String, dynamic> toMap() => {
    'name': name.trim(),
    'firstName': firstName.trim(),
    'lastName': lastName.trim(),
    'address': address.trim(),
    'apt': apt.trim(),
    'city': city.trim(),
    'province': province.trim(),
    'country': country.trim(),
    'postalCode': postalCode.trim(),
    'phone': phone.trim(),
    'mobile': mobile.trim(),
    'email': email.trim(),
    'contacts': contacts.map((c) => c.toMap()).toList(),
    'noFixedAddress': noFixedAddress,
  };

  String get displayName => name;

  List<ClientContact> get displayContact => contacts;
}
