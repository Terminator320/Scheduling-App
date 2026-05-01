import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:scheduling/features/clients/models/client_record.dart';

class ClientService {
  final CollectionReference<Map<String, dynamic>> _clients = FirebaseFirestore
      .instance
      .collection('clients');
  // Reuse identical search results while this service instance is alive.
  final Map<String, List<ClientRecord>> _searchCache = {};

  Future<void> addClient(ClientRecord client) async {
    await _clients.add({
      ...client.toMap(), //spread operator merges the map fields
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

  Stream<List<ClientRecord>> clientsStream({int? limit}) {
    Query<Map<String, dynamic>> query = _clients.orderBy(
      'createdAt',
      descending: true,
    );
    if (limit != null) query = query.limit(limit);

    return query.snapshots().map(
      (snapshot) =>
          snapshot.docs.map((doc) => ClientRecord.fromDoc(doc)).toList(),
    );
  }

  Future<List<ClientRecord>> searchClients(String query) async {
    final q = query.trim();
    if (!ClientSearchPolicy.shouldSearch(q)) return [];

    final cacheKey = ClientSearchPolicy.cacheKey(q);
    final cached = _searchCache[cacheKey];
    if (cached != null) return cached;

    // Normalize text so searches are case-insensitive and accent-insensitive.
    String normalize(String value) {
      return value
          .toLowerCase()
          .replaceAll(RegExp(r'[àáâãäå]'), 'a')
          .replaceAll(RegExp(r'[èéêë]'), 'e')
          .replaceAll(RegExp(r'[ìíîï]'), 'i')
          .replaceAll(RegExp(r'[òóôõö]'), 'o')
          .replaceAll(RegExp(r'[ùúûü]'), 'u')
          .replaceAll(RegExp(r'[ç]'), 'c')
          .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
          .trim();
    }

    String digitsOnly(String value) => value.replaceAll(RegExp(r'\D'), '');

    final normalizedQuery = normalize(q);
    final queryDigits = digitsOnly(q);

    final snapshot = await _clients
        .orderBy('createdAt', descending: true)
        .limit(ClientSearchPolicy.serverReadLimit)
        .get();

    final scoredClients = <MapEntry<int, ClientRecord>>[];

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final client = ClientRecord.fromDoc(doc);

      final contacts = (data['contacts'] as List?) ?? const [];
      final contactSearchText = contacts
          .whereType<Map>()
          .map((contact) {
            final map = Map<String, dynamic>.from(contact);
            return [
              map['name'],
              map['phone'],
              map['email'],
            ].whereType<Object>().map((v) => v.toString()).join(' ');
          })
          .join(' ');

      final searchableText = normalize(
        [
          data['businessName'],
          data['name'],
          data['phone'],
          data['email'],
          data['address'],
          data['city'],
          data['province'],
          data['postalCode'],
          data['country'],
          contactSearchText,
        ].whereType<Object>().map((v) => v.toString()).join(' '),
      );

      final displayName = normalize(client.displayName);
      final name = normalize(data['name']?.toString() ?? '');
      final businessName = normalize(data['businessName']?.toString() ?? '');
      final phoneDigits = digitsOnly(data['phone']?.toString() ?? '');
      final contactsDigits = digitsOnly(contactSearchText);

      final matchesText = searchableText.contains(normalizedQuery);
      final matchesPhone =
          queryDigits.isNotEmpty &&
          (phoneDigits.contains(queryDigits) ||
              contactsDigits.contains(queryDigits));

      if (!matchesText && !matchesPhone) continue;

      var score = 100;
      if (displayName == normalizedQuery || phoneDigits == queryDigits) {
        score = 0;
      } else if (displayName.startsWith(normalizedQuery) ||
          businessName.startsWith(normalizedQuery) ||
          name.startsWith(normalizedQuery)) {
        score = 1;
      } else if (queryDigits.isNotEmpty &&
          phoneDigits.startsWith(queryDigits)) {
        score = 2;
      } else if (displayName.contains(normalizedQuery) ||
          businessName.contains(normalizedQuery) ||
          name.contains(normalizedQuery)) {
        score = 3;
      } else if (queryDigits.isNotEmpty &&
          (phoneDigits.contains(queryDigits) ||
              contactsDigits.contains(queryDigits))) {
        score = 4;
      } else {
        score = 5;
      }

      scoredClients.add(MapEntry(score, client));
    }

    scoredClients.sort((a, b) {
      final scoreCompare = a.key.compareTo(b.key);
      if (scoreCompare != 0) return scoreCompare;
      return a.value.displayName.toLowerCase().compareTo(
        b.value.displayName.toLowerCase(),
      );
    });

    final results = scoredClients.take(25).map((entry) => entry.value).toList();
    _searchCache[cacheKey] = results;
    return results;
  }

  Future<ClientRecord?> getClientById(String id) async {
    final doc = await _clients.doc(id).get();
    if (!doc.exists) return null;
    return ClientRecord.fromDoc(doc);
  }
}

class ClientSearchPolicy {
  // Avoid broad reads for one-letter searches, but allow short phone searches.
  static const int minimumTextLength = 2;
  static const int minimumPhoneDigits = 3;
  static const int serverReadLimit = 1000;

  static bool shouldSearch(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return false;
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= minimumPhoneDigits) return true;
    return _normalize(trimmed).length >= minimumTextLength;
  }

  static String cacheKey(String query) => _normalize(query);

  static String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[àáâãäå]'), 'a')
        .replaceAll(RegExp(r'[èéêë]'), 'e')
        .replaceAll(RegExp(r'[ìíîï]'), 'i')
        .replaceAll(RegExp(r'[òóôõö]'), 'o')
        .replaceAll(RegExp(r'[ùúûü]'), 'u')
        .replaceAll(RegExp(r'[ç]'), 'c')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
  }
}
