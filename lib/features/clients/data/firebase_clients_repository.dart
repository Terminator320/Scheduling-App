import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show compute;

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/clients/domain/clients_repository.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/domain/policies/client_search_policy.dart';

class FirebaseClientsRepository implements ClientsRepository {
  FirebaseClientsRepository(
    FirebaseFirestore firestore, {
    AppLogger? logger,
    DateTime Function()? clock,
  }) : _clients = firestore.collection('clients'),
       _logger = logger ?? AppLogger(),
       _clock = clock ?? DateTime.now;

  final CollectionReference<Map<String, dynamic>> _clients;
  final AppLogger _logger;

  /// Injectable time source so the search-cache TTL is testable.
  final DateTime Function() _clock;

  // Bounded LRU of recent search results. The repository is a long-lived
  // singleton, so an unbounded map would grow one entry per distinct query for
  // the whole session. Oldest entry is evicted past [_searchCacheMax].
  static const int _searchCacheMax = 50;

  /// How long a cached search result — and the scan window itself — may be
  /// served before being re-read. Local writes patch the caches immediately;
  /// this TTL is the safety net for writes made on other devices, so a doc
  /// written elsewhere may take up to this long to show up in (or drop out
  /// of) search. Mirrors FirebaseAppointmentsRepository.
  static const Duration _searchCacheTtl = Duration(minutes: 2);

  final Map<String, _CachedClientSearch> _searchCache = {};

  // The raw name-ordered scan window shared by every search: one read of up
  // to serverReadLimit docs serves all queries typed within the TTL, instead
  // of each distinct query re-reading the whole window.
  _CachedClientScanWindow? _scanWindow;

  bool _isFresh(DateTime fetchedAt) =>
      _clock().difference(fetchedAt) < _searchCacheTtl;

  void _cacheSearch(String key, List<ClientRecord> results) {
    _searchCache.remove(key);
    if (_searchCache.length >= _searchCacheMax) {
      _searchCache.remove(_searchCache.keys.first);
    }
    _searchCache[key] = _CachedClientSearch(results, _clock());
  }

  // Selective invalidation for LOCAL writes: patch the one written doc into
  // (or out of) the in-memory scan window instead of dropping it, so the next
  // search recomputes from memory with ZERO Firestore reads — the old
  // clear-all forced a full up-to-1000-doc re-read after every write. The
  // derived per-query results are cleared (recomputing them from the patched
  // window is cheap and runs off the UI thread), which also guarantees a
  // just-deleted client can never be served from a stale entry. Remote writes
  // can't reach this hook; the per-entry TTL covers those.
  void _applyLocalWrite(String id, Map<String, dynamic>? data) {
    final window = _scanWindow;
    if (window != null && _isFresh(window.fetchedAt)) {
      final docs = [
        for (final doc in window.docs)
          if (doc.id != id) doc,
        // Position within the window doesn't matter: matching is per-doc and
        // the final ordering comes from the relevance sort, not window order.
        if (data != null) (id: id, data: data),
      ];
      _scanWindow = _CachedClientScanWindow(docs, window.fetchedAt);
    } else {
      _scanWindow = null;
    }
    _searchCache.clear();
  }

  // Stored `name` of each page-boundary doc, keyed by doc id. The field-value
  // cursor must use the exact value Firestore ordered by, and
  // ClientRecord.name falls back to `businessName` for legacy docs whose
  // stored name is empty — using that fallback as the cursor value would skip
  // every doc sorted between '' and the business name. One small entry per
  // page boundary, so growth is negligible.
  final Map<String, String> _pageBoundaryNames = {};

  @override
  Future<List<ClientRecord>> fetchClientsPage({
    required int limit,
    ClientRecord? after,
  }) async {
    // Alphabetical by name (ascending), with the doc id as an explicit
    // tiebreaker so the cursor can be plain field values — no extra read (and
    // serial round-trip) to refetch the boundary doc per page — without
    // skipping or duplicating clients that share a name (Firestore cursors on
    // equal values are otherwise ambiguous). Mirrors fetchHistoryPage. NOTE:
    // like any Firestore orderBy this excludes docs missing `name`; every
    // client write sets it, so that holds.
    var query = _clients.orderBy('name').orderBy(FieldPath.documentId);
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
  Future<List<ClientRecord>> fetchClientsCreatedSince(DateTime since) async {
    // Defensive ceiling consistent with the other windowed reads: the
    // dashboard range is small in practice, but never issue an unbounded query.
    final snapshot = await _clients
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .orderBy('createdAt')
        .limit(ClientSearchPolicy.serverReadLimit)
        .get();
    return snapshot.docs
        .map((doc) => ClientRecord.fromMap(doc.id, doc.data()))
        .toList();
  }

  @override
  Future<ClientRecord> addClient(ClientRecord client) async {
    final map = _normalizedMap(client);
    final docRef = await _clients.add({
      ...map,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _applyLocalWrite(docRef.id, map);
    return client.copyWith(id: docRef.id);
  }

  @override
  Future<void> updateClient(ClientRecord client) async {
    final map = _normalizedMap(client);
    await _clients.doc(client.id).update({
      ...map,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _applyLocalWrite(client.id, map);
  }

  @override
  Future<void> deleteClient(String id) async {
    await _clients.doc(id).delete();
    _applyLocalWrite(id, null);
  }

  @override
  Future<List<ClientRecord>> searchClients(String query) async {
    final q = query.trim();
    if (!ClientSearchPolicy.shouldSearch(q)) return [];

    final cacheKey = ClientSearchPolicy.cacheKey(q);
    final cached = _searchCache[cacheKey];
    if (cached != null && _isFresh(cached.fetchedAt)) {
      _cacheSearch(cacheKey, cached.results); // mark most-recently-used
      return cached.results;
    }
    _searchCache.remove(cacheKey);

    final window = await _clientScanWindow();
    if (window == null) return const [];

    // Parsing + normalizing + scoring up to serverReadLimit docs is CPU work
    // (8 regex passes over 13 fields per doc) — run it off the UI thread.
    final results = await compute(
      matchClientDocs,
      ClientSearchScan(docs: window.docs, query: q),
    );
    _cacheSearch(cacheKey, results);
    return results;
  }

  /// The raw name-ordered window of clients every search scans, served from
  /// cache while fresh so successive queries share one read.
  Future<_CachedClientScanWindow?> _clientScanWindow() async {
    final cached = _scanWindow;
    if (cached != null && _isFresh(cached.fetchedAt)) return cached;

    final QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      // Order by `name` (like fetchClientsPage), NOT createdAt: Firestore
      // excludes any doc missing the orderBy field, and legacy business-only
      // docs may lack createdAt — ordering by createdAt made them unsearchable.
      // `name` is set on every write, so this keeps all clients in scope.
      snapshot = await _clients
          .orderBy('name')
          .limit(ClientSearchPolicy.serverReadLimit)
          .get();
    } on FirebaseException catch (e, st) {
      _logger.warn('CLI-SEARCH searchClients failed', e, st);
      return null;
    }

    final window = _CachedClientScanWindow(
      [
        for (final doc in snapshot.docs) (id: doc.id, data: doc.data()),
      ],
      _clock(),
    );
    _scanWindow = window;
    return window;
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

/// One raw doc of the client scan window — kept as plain id + data so the
/// payload crosses the `compute` isolate boundary without Firestore handles.
typedef RawClientDoc = ({String id, Map<String, dynamic> data});

/// `compute` payload for [matchClientDocs].
class ClientSearchScan {
  const ClientSearchScan({required this.docs, required this.query});

  final List<RawClientDoc> docs;
  final String query;
}

/// Parses the scan window and returns the clients matching
/// [ClientSearchScan.query] across all fields (name, business name, person
/// name, phone/mobile, email, address, contacts), relevance-scored then
/// alphabetical. Matching goes through [ClientSearchPolicy] — the single
/// source of matching truth. Top-level so `compute` can run it in a
/// background isolate; [ClientRecord]s are plain Dart objects, so
/// constructing and returning them from the isolate is safe.
List<ClientRecord> matchClientDocs(ClientSearchScan scan) {
  final normalizedQuery = ClientSearchPolicy.normalize(scan.query);
  final queryDigits = ClientSearchPolicy.digitsOnly(scan.query);

  final scoredClients = <MapEntry<int, ClientRecord>>[];

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

    scoredClients.add(MapEntry(score, client));
  }

  scoredClients.sort((a, b) {
    final scoreCompare = a.key.compareTo(b.key);
    if (scoreCompare != 0) return scoreCompare;
    return a.value.displayName.toLowerCase().compareTo(
      b.value.displayName.toLowerCase(),
    );
  });

  return scoredClients
      .take(ClientSearchPolicy.resultDisplayLimit)
      .map((entry) => entry.value)
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
