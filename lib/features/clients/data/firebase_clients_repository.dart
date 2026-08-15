import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show compute;

import 'package:scheduling/core/logging/app_logger.dart';
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

  // Bounded LRU cache — once it hits _searchCacheMax entries, the oldest one gets evicted
  // so this can't grow without limit.
  static const int _searchCacheMax = 50;

  /// Cache TTL for search results and the scan window. Local writes patch the cache
  /// immediately, so this TTL is really just a safety net for remote writes.
  static const Duration _searchCacheTtl = Duration(minutes: 2);

  final Map<String, _CachedClientSearch> _searchCache = {};

  // Shared name-ordered scan window serving all queries within the TTL.
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

  // For local writes we patch the written doc into the scan window directly, so
  // search can recompute without an extra read. A null [data] means the doc is
  // gone (a delete) and is dropped rather than re-appended — one owner for the
  // whole window/cache-invalidation contract.
  void _patchWindow(String id, {Map<String, dynamic>? data}) {
    final window = _scanWindow;
    if (window != null && _isFresh(window.fetchedAt)) {
      // Merged over the cached doc, never substituted for it: `toMap()` emits
      // user-owned fields only, so a plain replace would drop the
      // function-owned `jobCount`/`createdAt` and blank the count on every
      // search and type-filter result until the window's TTL expired.
      final previous = window.docs
          .where((doc) => doc.id == id)
          .firstOrNull
          ?.data;
      final docs = [
        for (final doc in window.docs)
          if (doc.id != id) doc,
        // Where it lands in the window doesn't matter — matching happens per-doc, and the
        // final order comes from the relevance sort anyway.
        if (data != null) (id: id, data: {...?previous, ...data}),
      ];
      _scanWindow = _CachedClientScanWindow(docs, window.fetchedAt);
    } else {
      _scanWindow = null;
    }
    _searchCache.clear();
  }

  // Page-boundary doc names keyed by id. The cursor needs the exact Firestore `name`
  // value, not the `businessName` fallback, or we'd end up skipping docs.
  //
  // BOUNDED, like `_searchCache` beside it: this repository is a session-long
  // singleton and this map gains an entry per page fetched, so unbounded it
  // only ever grows. It is deliberately capped rather than CLEARED on write —
  // dropping a live boundary is not free, since the fallback `after.name`
  // carries the `businessName` substitution for a legacy business-only doc and
  // would page straight past it. The cap is far deeper than any list is
  // scrolled, and eviction is oldest-first, so a boundary still in use stays.
  final Map<String, String> _pageBoundaryNames = {};

  /// Page boundaries retained — ~`_clientsPageSize` × this many clients deep.
  static const _pageBoundaryMax = 200;

  @override
  Future<List<ClientRecord>> fetchClientsPage({
    required int limit,
    ClientRecord? after,
  }) async {
    // Archived clients are filtered out SERVER-side, so the server still fills
    // a whole page: `items.last` stays the true cursor and the list's
    // `pages.last.length < pageSize` end-of-list test stays valid. Filtering
    // here in Dart instead would shorten a full server page and truncate the
    // list permanently at the first archived client.
    //
    // Firestore excludes docs missing a filtered field, so this depends on
    // every client doc carrying `archived` — see the backfill script and the
    // two create paths (`_normalizedMap` and Wave `importCustomers`).
    //
    // Ordered alphabetically by name (with doc id as tiebreaker) to avoid skipping/duplicating clients with shared names.
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
    // Cap this so a windowed read can never turn into an unbounded query.
    // DESCENDING is load-bearing: the cap truncates the far end, and every
    // consumer renders newest-first, so ascending would drop the newest
    // clients — the ones the dashboard exists to show — and keep the oldest.
    // The same single-field index serves both directions.
    final snapshot = await _clients
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .orderBy('createdAt', descending: true)
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
    // Via the callable, not a direct doc delete: `allow delete` on /clients is
    // withdrawn, because rules cannot express "only when this client has no
    // appointments" and a direct delete would orphan the job history.
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
    // Drops the doc out of the cached window so search and the filters stop
    // returning it without paying for a fresh read.
    _patchWindow(id);
  }

  @override
  Future<void> setClientArchived(String id, {required bool archived}) async {
    await _clients.doc(id).update({
      'archived': archived,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    // Merges over the cached doc rather than replacing it — see _patchWindow.
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
    // Sort key computed once per record rather than twice per comparison
    // (same shape as fetchClientsByType).
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
    // Sort key comes from displayName (so legacy business-only docs still order
    // by their businessName fallback) but is computed once per record rather
    // than twice per comparison.
    final matches = [
      for (final doc in window.docs)
        // Archived clients are out of the type filter for the same reason
        // they're out of the list — the Archived chip is where they live.
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

  /// The raw, name-ordered window of clients every search scans. Served from cache so
  /// successive queries can share a single read.
  Future<_CachedClientScanWindow?> _clientScanWindow() async {
    final cached = _scanWindow;
    if (cached != null && _isFresh(cached.fetchedAt)) return cached;
    // Drop the expired window rather than merely declining to use it. This
    // repository is a non-autoDispose singleton, so up to 1000 raw doc maps
    // otherwise stayed pinned for the whole session after one search. The next
    // search re-reads either way.
    _scanWindow = null;

    final QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      // Order by `name`, not createdAt, so legacy business-only docs stay searchable —
      // `name` is the one field that's set on every write.
      snapshot = await _clients
          .orderBy('name')
          .limit(ClientSearchPolicy.serverReadLimit)
          .get();
    } on FirebaseException catch (e, st) {
      _logger.warn('CLI-SEARCH searchClients failed', e, st);
      return null;
    }

    if (snapshot.docs.length >= ClientSearchPolicy.serverReadLimit) {
      // Ordered by `name`, so at the cap this window is the alphabetically
      // FIRST N clients — everything past that point is invisible to search,
      // to the type-filter chips and to the Archived chip, all at once and
      // with no error anywhere. It arrives gradually as the roster grows,
      // which is exactly the kind of failure nobody reports. Same posture as
      // `_mapRangeSnapshot` in the appointments repository.
      _logger.warn(
        'CLI-SEARCH scan window hit the ${ClientSearchPolicy.serverReadLimit}'
        '-doc cap — search and the filters are seeing a prefix of the roster',
      );
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

/// Raw doc without Firestore handles, safe to cross `compute` isolate boundary.
typedef RawClientDoc = ({String id, Map<String, dynamic> data});

/// `compute` payload for [matchClientDocs].
class ClientSearchScan {
  const ClientSearchScan({required this.docs, required this.query});

  final List<RawClientDoc> docs;
  final String query;
}

/// Parses scan window and returns clients matching [ClientSearchScan.query] across all fields with relevance scoring.
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

    // Resolved once per record: `displayName` is an uncached getter that runs
    // `stripPhone` twice, and this loop walks the whole 1000-doc scan window.
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

    // Whether a client matches is ClientSearchPolicy's call, not this file's.
    // This used to be a hand-rolled index off the raw map, and it had already
    // drifted: it kept client digits and contact digits in two strings while
    // the policy concatenates all of them into one, so a query spanning both
    // (client phone tail + contact phone head) matched in the instant local
    // filter and then vanished when this debounced read landed. Only the
    // relevance SCORING below stays local.
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

    // The sort key is computed HERE, once per record, rather than twice per
    // comparison — the comparator below runs over the whole match set before
    // `.take`. Same rule as `fetchClientsByType`.
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
