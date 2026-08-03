import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:scheduling/core/utils/firestore_parsing.dart';
import 'package:scheduling/features/clients/domain/models/client_type.dart';

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
    @Default(ClientType.unset) ClientType type,
    @Default('') String accessNotes,
    @Default('') String onSiteManager,
    @Default('') String billingTerms,
    @Default(false) bool autoInvoice,
    // Legacy pre-Wave-reshape field, READ-ONLY — never emitted in toMap, and
    // no UI edits it. Carried only so search can still reach it: `name` falls
    // back to it when blank, but a legacy doc holding BOTH a name and a
    // different business name would otherwise be unfindable by the business.
    @Default('') String businessName,
    // Function-owned absolute recount — never emitted in toMap, and null until
    // the trigger has written it once.
    @Default(null) int? jobCount,
    // Read-only server timestamp used for dashboard trends — never emitted in toMap.
    DateTime? createdAt,
    // Wave projection — read-only and function-owned, so it's omitted from toMap
    // per firestore.rules.
    @Default(null) String? waveCustomerId,
    @Default('') String waveSyncState,
    @Default(null) String? waveSyncError,
  }) = _ClientRecord;
  const ClientRecord._();

  factory ClientRecord.fromMap(String id, Map<String, dynamic> data) {
    final rawContacts = (data['contacts'] as List?) ?? const [];
    final wave = (data['wave'] as Map?)?.cast<String, dynamic>();
    // Back-compat for legacy `businessName` — keeps unnamed business docs
    // visible and searchable. Two halves: `name` falls back to it when blank
    // (which is the documented legacy shape), and it is ALSO carried through
    // verbatim so ClientSearchPolicy can index it — a doc holding both a name
    // and a different business name is findable by either.
    final businessName = (data['businessName'] ?? '').toString();
    final rawName = (data['name'] ?? '').toString();
    final name = rawName.trim().isNotEmpty ? rawName : businessName;
    return ClientRecord(
      id: id,
      name: name,
      businessName: businessName,
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
      type: ClientType.fromRaw(data['type']?.toString()),
      accessNotes: (data['accessNotes'] ?? '').toString(),
      onSiteManager: (data['onSiteManager'] ?? '').toString(),
      billingTerms: (data['billingTerms'] ?? '').toString(),
      autoInvoice: (data['autoInvoice'] as bool?) ?? false,
      jobCount: (data['jobCount'] as num?)?.toInt(),
      createdAt: firestoreDateTime(data['createdAt']),
      waveCustomerId: data['waveCustomerId']?.toString(),
      waveSyncState: (wave?['syncState'] ?? '').toString(),
      waveSyncError: wave?['syncError']?.toString(),
    );
  }

  /// User-owned fields only. `waveCustomerId`/`wave`/`jobCount` are function-owned
  /// and get rejected by the update rule, so they're left out here.
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
    'type': type.raw,
    'accessNotes': accessNotes.trim(),
    'onSiteManager': onSiteManager.trim(),
    'billingTerms': billingTerms.trim(),
    'autoInvoice': autoInvoice,
  };

  String get displayName => name;
}
