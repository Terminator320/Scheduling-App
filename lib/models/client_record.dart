import 'package:cloud_firestore/cloud_firestore.dart';

class ClientContact {
  String name;
  String phone;
  String email;

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
    required this.contacts,
  });

  factory ClientRecord.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};
    final rawContacts = (data['contacts'] as List?) ?? [];

    return ClientRecord(
      id: doc.id,
      businessName: data['businessName'] ?? '',
      name: data['name'] ?? '',
      address: data['address'] ?? '',
      phone: data['phone'] ?? '',
      email: data['email'] ?? '',
      contacts: rawContacts
          .whereType<Map>()
          .map((contact) => ClientContact.fromMap(
        Map<String, dynamic>.from(contact),
      ))
          .toList(),
    );
  }
}