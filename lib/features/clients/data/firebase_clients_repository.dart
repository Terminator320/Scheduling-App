import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:scheduling/features/clients/domain/clients_repository.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/domain/policies/client_search_policy.dart';

class FirebaseClientsRepository implements ClientsRepository {
  FirebaseClientsRepository(FirebaseFirestore firestore)
    : _clients = firestore.collection('clients');

  final CollectionReference<Map<String, dynamic>> _clients;
  // In-memory only — cleared on app restart, reducing Firestore reads within a session.
  final Map<String, List<ClientRecord>> _searchCache = {};

  @override
  Stream<List<ClientRecord>> watchClients({int? limit}) {
    var query = _clients.orderBy(
      'createdAt',
      descending: true,
    );
    if (limit != null) query = query.limit(limit);

    return query.snapshots().map(
      (snapshot) => snapshot.docs
          .map((doc) => ClientRecord.fromMap(doc.id, doc.data()))
          .toList(),
    );
  }

  @override
  Future<ClientRecord?> getClientById(String id) async {
    final doc = await _clients.doc(id).get();
    if (!doc.exists) return null;
    return ClientRecord.fromMap(doc.id, doc.data() ?? {});
  }

  @override
  Future<void> addClient(ClientRecord client) async {
    await _clients.add({
      ..._normalizedMap(client),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> updateClient(ClientRecord client) async {
    await _clients.doc(client.id).update({
      ..._normalizedMap(client),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> deleteClient(String id) async {
    await _clients.doc(id).delete();
  }

  @override
  Future<List<ClientRecord>> searchClients(String query) async {
    final q = query.trim();
    if (!ClientSearchPolicy.shouldSearch(q)) return [];

    final cacheKey = ClientSearchPolicy.cacheKey(q);
    final cached = _searchCache[cacheKey];
    if (cached != null) return cached;

    final normalizedQuery = ClientSearchPolicy.normalize(q);
    final queryDigits = ClientSearchPolicy.digitsOnly(q);

    final snapshot = await _clients
        .orderBy('createdAt', descending: true)
        .limit(ClientSearchPolicy.serverReadLimit)
        .get();

    final scoredClients = <MapEntry<int, ClientRecord>>[];

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final client = ClientRecord.fromMap(doc.id, data);

      final contacts = (data['contacts'] as List?) ?? const [];
      final contactSearchText = contacts
          .whereType<Map<Object?, Object?>>()
          .map((contact) {
            final map = Map<String, dynamic>.from(contact);
            return [
              map['name'],
              map['phone'],
              map['email'],
            ].whereType<Object>().map((v) => v.toString()).join(' ');
          })
          .join(' ');

      final searchableText = ClientSearchPolicy.normalize(
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

      final displayName = ClientSearchPolicy.normalize(client.displayName);
      final name = ClientSearchPolicy.normalize(
        data['name']?.toString() ?? '',
      );
      final businessName = ClientSearchPolicy.normalize(
        data['businessName']?.toString() ?? '',
      );
      final phoneDigits = ClientSearchPolicy.digitsOnly(
        data['phone']?.toString() ?? '',
      );
      final contactsDigits = ClientSearchPolicy.digitsOnly(contactSearchText);

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

    final results = scoredClients
        .take(ClientSearchPolicy.resultDisplayLimit)
        .map((entry) => entry.value)
        .toList();
    _searchCache[cacheKey] = results;
    return results;
  }

  /// Normalizes the model on its way to Firestore: emails lower-cased +
  /// trimmed (CLAUDE.md invariant). All other string fields are already
  /// trimmed inside `ClientRecord.toMap()`.
  Map<String, dynamic> _normalizedMap(ClientRecord client) {
    final base = Map<String, dynamic>.from(client.toMap());
    final email = (base['email'] as String? ?? '').trim().toLowerCase();
    base['email'] = email;
    final contacts = base['contacts'] as List? ?? const [];
    base['contacts'] = contacts
        .whereType<Map>()
        .map((c) {
          final m = Map<String, dynamic>.from(c);
          final ce = (m['email'] as String? ?? '').trim().toLowerCase();
          m['email'] = ce;
          return m;
        })
        .toList();
    return base;
  }
}
