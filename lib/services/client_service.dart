import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/client_record.dart';

class ClientService {
  final CollectionReference<Map<String, dynamic>> _clients = FirebaseFirestore.instance.collection('clients');

  Future<void> addClient(ClientRecord client) async {
    await _clients.add({
      ... client.toMap(), //spread operator merges the map fields
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateClient(ClientRecord client) async {
    await _clients.doc(client.id).update({
      ...client.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }


  Future<void> deleteClient(String id) async {
    await _clients.doc(id).delete();
  }



  Stream<List<ClientRecord>> clientsStream() {
    return _clients
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
          snapshot.docs.map((doc) => ClientRecord.fromDoc(doc)).toList(),
    );
  }

  Future<List<ClientRecord>> searchClients(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    final isPhone = RegExp(r'^\d+$').hasMatch(q);

    final field = isPhone ? 'phone' : 'name';// no lowercase conversion

    final end = q.substring(0, q.length - 1) +
        String.fromCharCode(q.codeUnitAt(q.length - 1) + 1);

    final snapshot = await _clients
        .where(field, isGreaterThanOrEqualTo: q)
        .where(field, isLessThan: end)
        .limit(20)
        .get();

    return snapshot.docs.map((doc) => ClientRecord.fromDoc(doc)).toList();
  }



  Future<ClientRecord?> getClientById(String id) async {
    final doc = await _clients.doc(id).get();
    if (!doc.exists) return null;
    return ClientRecord.fromDoc(doc);
  }

}


