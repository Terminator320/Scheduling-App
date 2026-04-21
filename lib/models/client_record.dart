
import 'package:cloud_firestore/cloud_firestore.dart';

class ClientContact {
  final String name;
  final String phone;
  final String email;

  ClientContact({
    required this.name,
    required this.phone,
    required this.email,
  });

  factory ClientContact.fromMap(Map<String, dynamic> map) {
    return ClientContact(
      name: (map['name'] ?? '').toString(),
      phone: (map['phone'] ?? '').toString(),
      email: (map['email'] ?? '').toString(),
    );
  }


  Map<String, dynamic> toMap() {
    return {
      'name': name.trim(),
      'phone': phone.trim(),
      'email': email.trim(),
    };
  }
}

class ClientRecord {
  final String id;
  String businessName;
  String name;
  String address;
  String phone;
  String email;
  List<ClientContact> contacts;

  ClientRecord({
    required this.id,
    required this.businessName,
    required this.name,
    required this.address,
    required this.phone,
    required this.email,
    required this.contacts, //
  });

  Map<String, dynamic> toMap() {
    return {
      'businessName': businessName.trim(),
      'name': name.trim(),
      'address': address.trim(),
      'phone': phone.trim(),
      'email': email.trim(),
      'contacts': contacts.map((c) => c.toMap()).toList(),
    };
  }

  factory ClientRecord.fromMap(String id, Map<String, dynamic> data) {
    final rawContacts = (data['contacts'] as List?) ?? [];
    return ClientRecord(
      id: id,
      businessName: (data['businessName'] ?? '').toString(),
      name: (data['name'] ?? '').toString(),
      address: (data['address'] ?? '').toString(),
      phone: (data['phone'] ?? '').toString(),
      email: (data['email'] ?? '').toString(),
      contacts: rawContacts
          .whereType<Map>()
          .map((c) => ClientContact.fromMap(Map<String, dynamic>.from(c)))
          .toList(),
    );
  }

  factory ClientRecord.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return ClientRecord.fromMap(doc.id, doc.data() ?? {});
  }

  String get displayName =>
      businessName.isNotEmpty ? businessName : name;

  List<ClientContact> get displayContact =>
      contacts;
}