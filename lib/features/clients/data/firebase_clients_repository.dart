import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show compute;

import 'package:scheduling/core/data/paged_scan.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/validators/email_format.dart';
import 'package:scheduling/features/clients/domain/clients_failure.dart';
import 'package:scheduling/features/clients/domain/clients_repository.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/domain/models/client_type.dart';
import 'package:scheduling/features/clients/domain/policies/client_search_policy.dart';

class FirebaseClientsRepository implements ClientsRepository {
  FirebaseClientsRepository(
    FirebaseFirestore firestore, {
    FirebaseFunctions? functions,
    AppLogger? logger,
    DateTime Function()? clock,
  }) : _clients = firestore.collection('clients'),
       _functions = functions ?? FirebaseFunctions.instance,
       _logger = logger ?? AppLogger(),
       _clock = clock ?? DateTime.now;

  final CollectionReference<Map<String, dynamic>> _clients;
  final FirebaseFunctions _functions;
  final AppLogger _logger;

  /// Injectable time source so the search-cache TTL is testable.
  final DateTime Function() _clock;

  // Bounded LRU cache — once it hits _searchCacheMax entries, the oldest one
  // gets evicted so this can't grow without limit.
  static const int _searchCacheMax = 50;

  /// Cache TTL for search results and the scan window. Local writes patch the
  /// cache immediately, so this TTL is really just a safety net for remote
  /// writes.
  static const Duration _searchCacheTtl = Duration(minutes: 2);

  final Map<String, _CachedClientSearch> _searchCache = {};

  // Shared name-ordered scan window serving all queries within the TTL.
  _CachedClientScanWindow? _scanWindow;

  static const int _clientScanPageSize = 500;

  /// Ceiling on the paged client scan windows. Archived clients are never
  /// deleted, so the roster only ever grows; without this the first committed
  /// keystroke walks the whole collection and copies every raw doc map across
  /// the `compute` isolate boundary.
  static const int _clientScanLimit = 5000;

  bool _isFresh(DateTime fetchedAt) =>
      _clock().difference(fetchedAt) < _searchCacheTtl;

  void _cacheSearch(String key, List<ClientRecord> results) {
    _searchCache.remove(key);
    if (_searchCache.length >= _searchCacheMax) {
      _searchCache.remove(_searchCache.keys.first);
    }
    _searchCache[key] = _CachedClientSearch(results, _clock());
  }

  // For local writes we patch the written doc into the scan window directly, so
  // search can recompute without an extra read. A null [data] means the doc is
  // gone (a delete) and is dropped rather than re-appended.
  void _patchWindow(String id, {Map<String, dynamic>? data}) {
    final window = _scanWindow;
    if (window != null && _isFresh(window.fetchedAt)) {
      final previous = window.docs
          .where((doc) => doc.id == id)
          .firstOrNull
          ?.data;
      final docs = [
        for (final doc in window.docs)
          if (doc.id != id) doc,
        if (data != null) (id: id, data: {...?previous, ...data}),
      ];
      _scanWindow = _CachedClientScanWindow(docs, window.fetchedAt);
    } else {
      _scanWindow = null;
    }
    _searchCache.clear();
  }

  // Page-boundary doc names keyed by id. The cursor needs the exact Firestore
  // `name` value, not the `businessName` fallback, or we'd end up skipping docs.
  final Map<String, String> _pageBoundaryNames = {};

  /// Page boundaries retained — ~`_clientsPageSize` × this many clients deep.
  static const _pageBoundaryMax = 200;

  @override
  Future<List<ClientRecord>> fetchClientsPage({
    required int limit,
    ClientRecord? after,
  }) async {
    var query = _clients
        .where('archived', isEqualTo: false)
        .orderBy('name')
        .orderBy(FieldPath.documentId);
    if (after != null) {
      query = query.startAfter([
        _pageBoundaryNames[after.id] ?? after.name,
        after.id,
      ]);
    }
    final snapshot = await query.limit(limit).get();
    final docs = snapshot.docs;
    if (docs.isNotEmpty) {
      final last = docs.last;
      _pageBoundaryNames.remove(last.id);
      if (_pageBoundaryNames.length >= _pageBoundaryMax) {
        _pageBoundaryNames.remove(_pageBoundaryNames.keys.first);
      }
      _pageBoundaryNames[last.id] = (last.data()['name'] ?? '').toString();
    }
    return docs.map((doc) => ClientRecord.fromMap(doc.id, doc.data())).toList();
  }

  @override
  Future<ClientRecord?> getClientById(String id) async {
    final doc = await _clients.doc(id).get();
    if (!doc.exists) return null;
    return ClientRecord.fromMap(doc.id, doc.data() ?? {});
  }

  @override
  Stream<ClientRecord?> watchClient(String id) => _clients
      .doc(id)
      .snapshots()
      .map(
        (doc) =>
            doc.exists ? ClientRecord.fromMap(doc.id, doc.data() ?? {}) : null,
      );

  @override
  Future<List<ClientRecord>> fetchClientsCreatedSince(DateTime since) async {
    final docs = await pageToCap(
      _clients
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
          .orderBy('createdAt', descending: true),
      pageSize: _clientScanPageSize,
      cap: _clientScanLimit,
      onCapReached: () => _logger.warn(
        'CLI-LIST createdSince scan hit the $_clientScanLimit-doc cap - '
        'older clients are not included',
      ),
    );
    return docs.map((doc) => ClientRecord.fromMap(doc.id, doc.data())).toList();
  }

  @override
  Future<ClientRecord> addClient(ClientRecord client) async {
    final map = _normalizedMap(client);
    final docRef = await _clients.add({
      ...map,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _patchWindow(docRef.id, data: map);
    return client.copyWith(id: docRef.id);
  }

  @override
  Future<void> updateClient(ClientRecord client) async {
    final map = _normalizedMap(client);
    await _clients.doc(client.id).update({
      ...map,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _patchWindow(client.id, data: map);
  }

  @override
  Future<void> deleteClient(String id) async {
    try {
      await _functions.httpsCallable('deleteClient').call<void>({
        'clientId': id,
      });
    } on FirebaseFunctionsException catch (e) {
      if (e.message == 'client-has-history') {
        throw const ClientsFailureHasHistory();
      }
      if (e.message == 'client-not-found') {
        throw const ClientsFailureNotFound();
      }
      rethrow;
    }
    _patchWindow(id);
  }

  @override
  Future<void> setClientArchived(String id, {required bool archived}) async {
    await _clients.doc(id).update({
      'archived': archived,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _patchWindow(id, data: {'archived': archived});
  }

  @override
  Future<List<ClientRecord>> fetchArchivedClients() async {
    final window = await _clientScanWindow();
    if (window == null) return const [];
    final matches = [
      for (final doc in window.docs)
        if (doc.data['archived'] == true)
          ClientRecord.fromMap(doc.id, doc.data),
    ];
    final keyed = [
      for (final record in matches)
        (sortKey: record.displayName.toLowerCase(), record: record),
    ]..sort((a, b) => a.sortKey.compareTo(b.sortKey));
    return [for (final entry in keyed) entry.record];
  }

  @override
  Future<List<ClientRecord>> fetchClientsByType(ClientType type) async {
    if (type == ClientType.unset) return const [];
    final window = await _clientScanWindow();
    if (window == null) return const [];
    final matches = [
      for (final doc in window.docs)
        if (doc.data['archived'] != true &&
            ClientType.fromRaw(doc.data['type']?.toString()) == type)
          ClientRecord.fromMap(doc.id, doc.data),
    ];
    final keyed = [
      for (final record in matches)
        (sortKey: record.displayName.toLowerCase(), record: record),
    ]..sort((a, b) => a.sortKey.compareTo(b.sortKey));
    return [for (final entry in keyed) entry.record];
  }

  @override
  Future<List<ClientRecord>> searchClients(String query) async {
    final q = query.trim();
    if (!ClientSearchPolicy.shouldSearch(q)) return [];

    final cacheKey = ClientSearchPolicy.cacheKey(q);
    final cached = _searchCache[cacheKey];
    if (cached != null && _isFresh(cached.fetchedAt)) {
      _cacheSearch(cacheKey, cached.results);
      return cached.results;
    }
    _searchCache.remove(cacheKey);

    final window = await _clientScanWindow();
    if (window == null) return const [];

    final results = await compute(
      matchClientDocs,
      ClientSearchScan(docs: window.docs, query: q),
    );
    _cacheSearch(cacheKey, results);
    return results;
  }

  Future<_CachedClientScanWindow?> _clientScanWindow() async {
    final cached = _scanWindow;
    if (cached != null && _isFresh(cached.fetchedAt)) return cached;
    _scanWindow = null;

    try {
      final scanned = await pageToCap(
        _clients.orderBy('name').orderBy(FieldPath.documentId),
        pageSize: _clientScanPageSize,
        cap: _clientScanLimit,
        onCapReached: () => _logger.warn(
          'CLI-SEARCH scan window hit the $_clientScanLimit-doc cap - '
          'clients past it are invisible to search and to the filter chips',
        ),
        advance: (query, last) =>
            query.startAfter([(last.data()['name'] ?? '').toString(), last.id]),
      );
      final docs = <RawClientDoc>[
        for (final doc in scanned) (id: doc.id, data: doc.data()),
      ];
      final window = _CachedClientScanWindow(docs, _clock());
      _scanWindow = window;
      return window;
    } on FirebaseException catch (e, st) {
      _logger.warn('CLI-SEARCH searchClients failed', e, st);
      return null;
    }
  }

  Map<String, dynamic> _normalizedMap(ClientRecord client) {
    final base = Map<String, dynamic>.from(client.toMap());
    base['email'] = normalizeEmail(base['email'] as String? ?? '');
    final contacts = base['contacts'] as List? ?? const [];
    base['contacts'] = contacts.whereType<Map<Object?, Object?>>().map((c) {
      final m = Map<String, dynamic>.from(c);
      m['email'] = normalizeEmail(m['email'] as String? ?? '');
      return m;
    }).toList();
    return base;
  }
}

/// Raw doc without Firestore handles, safe to cross `compute` isolate boundary.
typedef RawClientDoc = ({String id, Map<String, dynamic> data});

/// `compute` payload for [matchClientDocs].
class ClientSearchScan {
  const ClientSearchScan({required this.docs, required this.query});

  final List<RawClientDoc> docs;
  final String query;
}

/// Parses scan window and returns clients matching [ClientSearchScan.query]
/// across all fields with relevance scoring.
List<ClientRecord> matchClientDocs(ClientSearchScan scan) {
  final normalizedQuery = ClientSearchPolicy.normalize(scan.query);
  final queryDigits = ClientSearchPolicy.digitsOnly(scan.query);

  final scoredClients = <({int score, String sortKey, ClientRecord record})>[];

  for (final doc in scan.docs) {
    final data = doc.data;
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

    final rawDisplayName = client.displayName;
    final displayName = ClientSearchPolicy.normalize(rawDisplayName);
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

    if (!ClientSearchPolicy.entryMatches(
      ClientSearchPolicy.index(client),
      queryText: normalizedQuery,
      queryDigits: queryDigits,
    )) {
      continue;
    }

    var score = 100;
    if (displayName == normalizedQuery || phoneDigits == queryDigits) {
      score = 0;
    } else if (displayName.startsWith(normalizedQuery) ||
        personName.startsWith(normalizedQuery)) {
      score = 1;
    } else if (queryDigits.isNotEmpty && phoneDigits.startsWith(queryDigits)) {
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

    scoredClients.add((
      score: score,
      sortKey: rawDisplayName.toLowerCase(),
      record: client,
    ));
  }

  scoredClients.sort((a, b) {
    final scoreCompare = a.score.compareTo(b.score);
    if (scoreCompare != 0) return scoreCompare;
    return a.sortKey.compareTo(b.sortKey);
  });

  return scoredClients
      .take(ClientSearchPolicy.resultDisplayLimit)
      .map((entry) => entry.record)
      .toList();
}

class _CachedClientSearch {
  const _CachedClientSearch(this.results, this.fetchedAt);

  final List<ClientRecord> results;
  final DateTime fetchedAt;
}

class _CachedClientScanWindow {
  const _CachedClientScanWindow(this.docs, this.fetchedAt);

  final List<RawClientDoc> docs;
  final DateTime fetchedAt;
}
