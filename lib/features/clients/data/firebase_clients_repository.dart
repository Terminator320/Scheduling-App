import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:scheduling/features/clients/domain/clients_repository.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/domain/policies/client_search_policy.dart';

class FirebaseClientsRepository implements ClientsRepository {
  FirebaseClientsRepository(FirebaseFirestore firestore)
    : _clients = firestore.collection('clients');

  final CollectionReference<Map<String, dynamic>> _clients;

  // Bounded LRU of recent search results. The repository is a long-lived
  // singleton, so an unbounded map would grow one entry per distinct query for
  // the whole session. Oldest entry is evicted past [_searchCacheMax].
  static const int _searchCacheMax = 50;
  final Map<String, List<ClientRecord>> _searchCache = {};

  void _cacheSearch(String key, List<ClientRecord> results) {
    _searchCache.remove(key);
    if (_searchCache.length >= _searchCacheMax) {
      _searchCache.remove(_searchCache.keys.first);
    }
    _searchCache[key] = results;
  }

  @override
  Future<List<ClientRecord>> fetchClientsPage({
    required int limit,
    ClientRecord? after,
  }) async {
    // Alphabetical by name (ascending). NOTE: like any Firestore orderBy this
    // excludes docs missing `name`; every client write sets it, so that holds.
    var query = _clients.orderBy('name');
    if (after != null) {
      // Re-fetch the cursor doc so startAfterDocument reads its orderBy fields.
      // One extra read per page boundary — negligible and keeps the domain
      // layer free of Firestore DocumentSnapshot types.
      final afterDoc = await _clients.doc(after.id).get();
      if (afterDoc.exists) query = query.startAfterDocument(afterDoc);
    }
    final snapshot = await query.limit(limit).get();
    return snapshot.docs
        .map((doc) => ClientRecord.fromMap(doc.id, doc.data()))
        .toList();
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
    if (cached != null) {
      _cacheSearch(cacheKey, cached); // mark most-recently-used
      return cached;
    }

    final normalizedQuery = ClientSearchPolicy.normalize(q);
    final queryDigits = ClientSearchPolicy.digitsOnly(q);

    final QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await _clients
          .orderBy('createdAt', descending: true)
          .limit(ClientSearchPolicy.serverReadLimit)
          .get();
    } on FirebaseException catch (e, st) {
      debugPrint('[FirebaseClientsRepository] searchClients failed: $e');
      debugPrintStack(stackTrace: st);
      return const [];
    }

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
          data['name'],
          // Legacy business-only docs (pre-Wave reshape) keep their name under
          // `businessName`; index it so those clients stay searchable.
          data['businessName'],
          data['firstName'],
          data['lastName'],
          data['phone'],
          data['mobile'],
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
      final personName = ClientSearchPolicy.normalize(
        [
          data['firstName'],
          data['lastName'],
        ].whereType<Object>().map((v) => v.toString()).join(' '),
      );
      final phoneDigits = ClientSearchPolicy.digitsOnly(
        '${data['phone'] ?? ''} ${data['mobile'] ?? ''}',
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
          personName.startsWith(normalizedQuery)) {
        score = 1;
      } else if (queryDigits.isNotEmpty &&
          phoneDigits.startsWith(queryDigits)) {
        score = 2;
      } else if (displayName.contains(normalizedQuery) ||
          personName.contains(normalizedQuery)) {
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
    _cacheSearch(cacheKey, results);
    return results;
  }

  Map<String, dynamic> _normalizedMap(ClientRecord client) {
    final base = Map<String, dynamic>.from(client.toMap());
    final email = (base['email'] as String? ?? '').trim().toLowerCase();
    base['email'] = email;
    final contacts = base['contacts'] as List? ?? const [];
    base['contacts'] = contacts.whereType<Map<Object?, Object?>>().map((c) {
      final m = Map<String, dynamic>.from(c);
      final ce = (m['email'] as String? ?? '').trim().toLowerCase();
      m['email'] = ce;
      return m;
    }).toList();
    return base;
  }
}
