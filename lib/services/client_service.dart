import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/client_record.dart';

class ClientService {
  static final CollectionReference<Map<String, dynamic>> _clients =
  FirebaseFirestore.instance.collection('clients');

  static Future<void> addClient({
    required String businessName,
    required String name,
    required String address,
    required String phone,
    required String email,
    required List<ClientContact> contacts,
  }) async {
    await _clients.add({
      'businessName': businessName.trim(),
      'name': name.trim(),
      'address': address.trim(),
      'phone': phone.trim(),
      'email': email.trim(),
      'contacts': contacts.map((c) => c.toMap()).toList(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Stream<List<ClientRecord>> clientsStream() {
    return _clients
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
          snapshot.docs.map((doc) => ClientRecord.fromDoc(doc)).toList(),
    );
  }

  static Future<List<ClientRecord>> searchClients(String query) async {
    final q = query.trim().toLowerCase();

    if (q.isEmpty) {
      return [];
    }

    final snapshot = await _clients.get();

    return snapshot.docs
        .map((doc) => ClientRecord.fromDoc(doc))
        .where(
          (client) =>
      client.businessName.toLowerCase().contains(q) ||
          client.name.toLowerCase().contains(q) ||
          client.phone.toLowerCase().contains(q) ||
          client.email.toLowerCase().contains(q) ||
          client.contacts.any(
                (contact) =>
            contact.name.toLowerCase().contains(q) ||
                contact.phone.toLowerCase().contains(q) ||
                contact.email.toLowerCase().contains(q),
          ),
    )
        .toList();
  }

  static Future<void> updateClient({
    required String id,
    required String businessName,
    required String name,
    required String address,
    required String phone,
    required String email,
    required List<ClientContact> contacts,
  }) async {
    await _clients.doc(id).update({
      'businessName': businessName.trim(),
      'name': name.trim(),
      'address': address.trim(),
      'phone': phone.trim(),
      'email': email.trim(),
      'contacts': contacts.map((c) => c.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> deleteClient(String id) async {
    await _clients.doc(id).delete();
  }
}


