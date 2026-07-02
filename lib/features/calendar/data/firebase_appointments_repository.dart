import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show compute;

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/utils/retry.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/clients/domain/policies/client_search_policy.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

class FirebaseAppointmentsRepository implements AppointmentsRepository {
  FirebaseAppointmentsRepository(
    FirebaseFirestore firestore, {
    AppLogger? logger,
    DateTime Function()? clock,
  }) : _appointments = firestore.collection('appointments'),
       _logger = logger ?? AppLogger(),
       _clock = clock ?? DateTime.now;

  final CollectionReference<Map<String, dynamic>> _appointments;
  final AppLogger _logger;

  /// Injectable time source so the search-cache TTL is testable.
  final DateTime Function() _clock;

  // Bounded LRU of recent history-search results. The repository is a
  // long-lived singleton (it outlives the autoDispose historySearchProvider),
  // so re-searching a term reuses the result instead of re-scanning the
  // window. Mirrors FirebaseClientsRepository.
  static const int _searchCacheMax = 50;

  /// How long a cached search result — and the scan window itself — may be
  /// served before being re-read. Local writes invalidate immediately; this
  /// TTL is the safety net for writes made on other devices, so a doc written
  /// elsewhere may take up to this long to show up in (or drop out of) search.
  static const Duration _searchCacheTtl = Duration(minutes: 2);

  final Map<String, _CachedHistorySearch> _searchCache = {};

  // The raw newest-first scan window shared by every search: one read of up
  // to _historySearchScanLimit docs serves all queries typed within the TTL,
  // instead of each distinct query re-reading the whole window.
  _CachedHistoryScanWindow? _scanWindow;

  bool _isFresh(DateTime fetchedAt) =>
      _clock().difference(fetchedAt) < _searchCacheTtl;

  void _cacheSearch(String key, List<AppointmentRecord> results) {
    _searchCache.remove(key);
    if (_searchCache.length >= _searchCacheMax) {
      _searchCache.remove(_searchCache.keys.first);
    }
    _searchCache[key] = _CachedHistorySearch(results, _clock());
  }

  // Any LOCAL write can change which docs a query matches, so drop the search
  // caches (the scan window and the per-query results — nothing else is
  // cached) rather than serve stale results — or list a just-deleted
  // appointment that opens a detail view for a doc that no longer exists.
  // Remote writes can't reach this hook; the per-entry TTL covers those.
  void _invalidateSearchCache() {
    _searchCache.clear();
    _scanWindow = null;
    _localWrites.add(null);
  }

  // Broadcast so historySearchProvider (and any future watcher) can
  // self-invalidate on local writes; the repository is app-lifetime, so the
  // controller is never closed.
  final StreamController<void> _localWrites = StreamController.broadcast();

  @override
  Stream<void> get onLocalWrite => _localWrites.stream;

  @override
  String newDocId() => _appointments.doc().id;

  @override
  Future<AppointmentRecord?> getAppointmentById(String id) async {
    final doc = await _appointments.doc(id).get();
    if (!doc.exists) return null;
    return AppointmentRecord.fromMap(doc.id, doc.data() ?? {});
  }

  @override
  Future<void> addAppointment(AppointmentRecord appointment) =>
      addAppointments([appointment]);

  @override
  Future<void> addAppointments(List<AppointmentRecord> appointments) async {
    final batch = _appointments.firestore.batch();
    for (final appointment in appointments) {
      final doc = appointment.id == null
          ? _appointments.doc()
          : _appointments.doc(appointment.id);
      batch.set(doc, {
        ..._toFirestoreMap(appointment),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    _invalidateSearchCache();
  }

  @override
  Future<List<AppointmentRecord>> getSeries(String seriesId) async {
    final snapshot = await _appointments
        .where('seriesId', isEqualTo: seriesId)
        .get();
    return snapshot.docs
        .map((doc) => AppointmentRecord.fromMap(doc.id, doc.data()))
        .toList();
  }

  @override
  Future<void> rewriteSeries({
    required AppointmentRecord updated,
    required List<String> deleteIds,
    required List<AppointmentRecord> copies,
  }) async {
    // The surviving doc's pictures are excluded for the same stale-snapshot
    // reason as updateAppointment; the fresh copies are created with theirs.
    final batch = _appointments.firestore.batch()
      ..update(_appointments.doc(updated.id), {
        ..._toFirestoreMap(updated, includePictures: false),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    for (final id in deleteIds) {
      batch.delete(_appointments.doc(id));
    }
    for (final copy in copies) {
      batch.set(_appointments.doc(copy.id), {
        ..._toFirestoreMap(copy),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    _invalidateSearchCache();
  }

  @override
  Future<void> updateAppointment(AppointmentRecord appointment) async {
    if (appointment.id == null) return;
    // Updates never rewrite `pictures`: the in-memory record is a snapshot
    // from sheet-open time, so writing it back would erase photos appended by
    // a background upload that landed in between. Picture changes go through
    // appendAppointmentPictures/removeAppointmentPictures (arrayUnion/Remove)
    // instead; only document creation writes the full array.
    await _appointments.doc(appointment.id).update({
      ..._toFirestoreMap(appointment, includePictures: false),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _invalidateSearchCache();
  }

  @override
  Future<void> updateAppointments(List<AppointmentRecord> appointments) async {
    final records = [
      for (final a in appointments)
        if (a.id != null) a,
    ];
    if (records.isEmpty) return;
    // A transaction (not a plain batch) so a sibling deleted concurrently
    // (e.g. another admin removing a future visit) is skipped rather than
    // failing the whole apply-to-series save with NOT_FOUND and losing the
    // user's edit. Reads must precede writes inside the transaction.
    await _appointments.firestore.runTransaction((txn) async {
      final refs = [for (final r in records) _appointments.doc(r.id)];
      final snaps = await Future.wait([for (final ref in refs) txn.get(ref)]);
      for (var i = 0; i < records.length; i++) {
        if (!snaps[i].exists) continue;
        // Pictures excluded for the same stale-snapshot reason as
        // updateAppointment — each sibling keeps its own stored photos.
        txn.update(refs[i], {
          ..._toFirestoreMap(records[i], includePictures: false),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
    _invalidateSearchCache();
  }

  @override
  Future<void> appendAppointmentPictures(
    String id,
    List<AppointmentImage> pictures,
  ) async {
    if (pictures.isEmpty) return;
    // arrayUnion (not a whole-array rewrite) so a background upload finishing
    // after a concurrent edit save can only add its own photos, never erase
    // ones it didn't know about. Union dedups identical maps, which is safe:
    // every upload gets a unique storagePath/url.
    await _appointments.doc(id).update({
      'pictures': FieldValue.arrayUnion(
        pictures.map(_imageToFirestoreMap).toList(),
      ),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _invalidateSearchCache();
  }

  @override
  Future<void> removeAppointmentPictures(
    String id,
    List<AppointmentImage> pictures,
  ) async {
    if (pictures.isEmpty) return;
    await _appointments.doc(id).update({
      'pictures': FieldValue.arrayRemove(
        pictures.map(_imageToFirestoreMap).toList(),
      ),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _invalidateSearchCache();
  }

  static const _allowedStatuses = {
    'pending',
    'confirmed',
    'in_progress',
    'done',
    'cancelled',
  };

  @override
  Future<void> updateAppointmentStatus({
    required String id,
    required String status,
  }) async {
    final trimmed = status.trim();
    if (!_allowedStatuses.contains(trimmed)) {
      throw ArgumentError.value(
        status,
        'status',
        'must be one of $_allowedStatuses',
      );
    }
    await _appointments.doc(id).update({
      'status': trimmed,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _invalidateSearchCache();
  }

  @override
  Future<void> deleteAppointment(String id) => deleteAppointments([id]);

  @override
  Future<void> deleteAppointments(List<String> ids) async {
    final batch = _appointments.firestore.batch();
    for (final id in ids) {
      batch.delete(_appointments.doc(id));
    }
    await batch.commit();
    _invalidateSearchCache();
  }

  @override
  Stream<List<AppointmentRecord>> watchInRange(AppointmentDateRange range) {
    return retryStream(
      () => _appointments
          .where(
            'startTime',
            isGreaterThanOrEqualTo: Timestamp.fromDate(range.start),
          )
          .where('startTime', isLessThan: Timestamp.fromDate(range.end))
          .orderBy('startTime')
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map((doc) => AppointmentRecord.fromMap(doc.id, doc.data()))
                .toList(),
          ),
      retryWhen: _isAuthPropagationDenied,
    );
  }

  @override
  Future<List<AppointmentRecord>> fetchHistoryPage({
    required int limit,
    AppointmentRecord? after,
  }) async {
    // Newest-first, server-ordered + cursor-paged so the most recent history
    // is always returned (the old limit(500) had no orderBy, so it kept an
    // arbitrary doc-id slice and could drop recent visits past 500). The doc
    // id is an explicit orderBy tiebreaker so the cursor can be plain field
    // values — no extra read to refetch the boundary doc per page — without
    // skipping visits that share a startTime. Served by the existing
    // `appointments (status ASC, startTime ASC)` composite index (every index
    // implicitly ends on the doc id), scanned in reverse for the descending
    // order.
    var query = _appointments
        .where('status', whereIn: _historyStatuses)
        .orderBy('startTime', descending: true)
        .orderBy(FieldPath.documentId, descending: true);
    final afterId = after?.id;
    if (after != null && afterId != null) {
      query = query.startAfter([Timestamp.fromDate(after.startTime), afterId]);
    }
    final snapshot = await query.limit(limit).get();
    return snapshot.docs
        .map((doc) => AppointmentRecord.fromMap(doc.id, doc.data()))
        .toList();
  }

  static const List<String> _historyStatuses = ['done', 'cancelled'];

  // How many of the most-recent history docs a search scans. Bounded so a
  // search reads at most this many docs (mirrors the clients search window).
  static const int _historySearchScanLimit = 1000;

  @override
  Future<List<AppointmentRecord>> searchHistory(String query) async {
    final q = query.trim();
    if (!ClientSearchPolicy.shouldSearch(q)) return const [];

    final cacheKey = ClientSearchPolicy.cacheKey(q);
    final cached = _searchCache[cacheKey];
    if (cached != null && _isFresh(cached.fetchedAt)) {
      _cacheSearch(cacheKey, cached.results); // mark most-recently-used
      return cached.results;
    }
    _searchCache.remove(cacheKey);

    final window = await _historyScanWindow();
    if (window == null) return const [];

    // Parsing + matching up to _historySearchScanLimit docs is CPU work —
    // run it off the UI thread.
    final matches = await compute(
      matchHistoryDocs,
      HistorySearchScan(docs: window.docs, query: q),
    );
    _cacheSearch(cacheKey, matches);
    return matches;
  }

  /// The newest-first raw window of terminal visits every search scans,
  /// served from cache while fresh so successive queries share one read.
  Future<_CachedHistoryScanWindow?> _historyScanWindow() async {
    final cached = _scanWindow;
    if (cached != null && _isFresh(cached.fetchedAt)) return cached;

    final QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      // Same query shape as fetchHistoryPage, so the existing
      // (status, startTime) composite index serves it — no new index.
      snapshot = await _appointments
          .where('status', whereIn: _historyStatuses)
          .orderBy('startTime', descending: true)
          .limit(_historySearchScanLimit)
          .get();
    } on FirebaseException catch (e, st) {
      _logger.warn('HIST-SEARCH searchHistory failed', e, st);
      return null;
    }

    final window = _CachedHistoryScanWindow(
      [
        for (final doc in snapshot.docs) (id: doc.id, data: doc.data()),
      ],
      _clock(),
    );
    _scanWindow = window;
    return window;
  }

  @override
  Stream<List<AppointmentRecord>> watchForEmployeeInRange(
    String employeeId,
    AppointmentDateRange range,
  ) {
    return retryStream(
      () => _appointments
          .where('employeeIds', arrayContains: employeeId)
          .where(
            'startTime',
            isGreaterThanOrEqualTo: Timestamp.fromDate(range.start),
          )
          .where('startTime', isLessThan: Timestamp.fromDate(range.end))
          .orderBy('startTime')
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map((doc) => AppointmentRecord.fromMap(doc.id, doc.data()))
                .toList(),
          ),
      retryWhen: _isAuthPropagationDenied,
    );
  }

  @override
  Future<List<EmployeeRecord>> findBusyEmployees({
    required List<EmployeeRecord> candidates,
    required DateTime start,
    required DateTime end,
  }) async {
    if (candidates.isEmpty) return const [];

    final ids = candidates.map((e) => e.id).toList();

    // The 30-ID batches (whereArrayContainsAny limit) are independent —
    // query them in parallel.
    final queries = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
    for (var i = 0; i < ids.length; i += 30) {
      final batch = ids.sublist(i, i + 30 < ids.length ? i + 30 : ids.length);
      queries.add(
        _appointments
            .where('employeeIds', arrayContainsAny: batch)
            .where('startTime', isLessThan: Timestamp.fromDate(end))
            .where('endTime', isGreaterThan: Timestamp.fromDate(start))
            .get(),
      );
    }

    final busyIds = <String>{};
    for (final snapshot in await Future.wait(queries)) {
      for (final doc in snapshot.docs) {
        final data = doc.data();
        // Cancelled/done visits no longer occupy the slot. Filtered here
        // rather than in the query: a status whereIn would be a second
        // disjunctive clause, which Firestore can't combine with
        // arrayContainsAny.
        final status = (data['status'] ?? '').toString().toLowerCase();
        if (_terminalStatuses.contains(status)) continue;
        final empIds = data['employeeIds'] as List<dynamic>? ?? const [];
        busyIds.addAll(empIds.whereType<String>());
      }
    }

    return candidates.where((e) => busyIds.contains(e.id)).toList();
  }

  // Statuses that free the time slot ('completed' is the legacy alias of
  // 'done' — see AppointmentStatus.fromRaw).
  static const Set<String> _terminalStatuses = {
    'done',
    'completed',
    'cancelled',
  };

  Map<String, dynamic> _toFirestoreMap(
    AppointmentRecord appointment, {
    bool includePictures = true,
  }) {
    final base = Map<String, dynamic>.from(appointment.toMap());
    base['startTime'] = Timestamp.fromDate(appointment.startTime);
    base['endTime'] = Timestamp.fromDate(appointment.endTime);
    if (includePictures) {
      base['pictures'] = appointment.pictures
          .map(_imageToFirestoreMap)
          .toList();
    } else {
      base.remove('pictures');
    }
    return base;
  }

  Map<String, dynamic> _imageToFirestoreMap(AppointmentImage image) {
    return {
      'url': image.url,
      'storagePath': image.storagePath,
      'fileName': image.fileName,
      'uploadedAt': image.uploadedAt == null
          ? null
          : Timestamp.fromDate(image.uploadedAt!),
    };
  }
}

/// One raw doc of the history scan window — kept as plain id + data so the
/// payload crosses the `compute` isolate boundary without Firestore handles.
typedef RawHistoryDoc = ({String id, Map<String, dynamic> data});

/// `compute` payload for [matchHistoryDocs].
class HistorySearchScan {
  const HistorySearchScan({required this.docs, required this.query});

  final List<RawHistoryDoc> docs;
  final String query;
}

/// Parses the scan window and returns the visits matching [HistorySearchScan.query]
/// by client name, employee name, or phone digits — newest-first, mirroring
/// the window order. Top-level so `compute` can run it in a background
/// isolate; [AppointmentRecord]s are plain Dart objects, so constructing and
/// returning them from the isolate is safe.
List<AppointmentRecord> matchHistoryDocs(HistorySearchScan scan) {
  final normalizedQuery = ClientSearchPolicy.normalize(scan.query);
  final queryDigits = ClientSearchPolicy.digitsOnly(scan.query);

  final matches = <AppointmentRecord>[];
  for (final doc in scan.docs) {
    final a = AppointmentRecord.fromMap(doc.id, doc.data);
    final matchesClient =
        normalizedQuery.isNotEmpty &&
        ClientSearchPolicy.normalize(a.clientName).contains(normalizedQuery);
    final matchesEmployee =
        normalizedQuery.isNotEmpty &&
        a.employeeNames.any(
          (e) => ClientSearchPolicy.normalize(e).contains(normalizedQuery),
        );
    final matchesPhone =
        queryDigits.isNotEmpty &&
        ClientSearchPolicy.digitsOnly(a.clientPhone).contains(queryDigits);
    if (matchesClient || matchesEmployee || matchesPhone) matches.add(a);
  }
  return matches;
}

class _CachedHistorySearch {
  const _CachedHistorySearch(this.results, this.fetchedAt);

  final List<AppointmentRecord> results;
  final DateTime fetchedAt;
}

class _CachedHistoryScanWindow {
  const _CachedHistoryScanWindow(this.docs, this.fetchedAt);

  final List<RawHistoryDoc> docs;
  final DateTime fetchedAt;
}

// A freshly signed-in user's ID token and `usersByUid` role bridge can lag the
// auth state, so the first appointments listen comes back permission-denied even
// though the read is authorized (the same race login's _retryOnAuthPropagation
// guards). Re-subscribing after a short delay succeeds; a genuine denial simply
// survives every retry and surfaces as before.
bool _isAuthPropagationDenied(Object error) =>
    error is FirebaseException && error.code == 'permission-denied';
