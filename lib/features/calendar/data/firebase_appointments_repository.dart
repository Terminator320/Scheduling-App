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
import 'package:uuid/uuid.dart';

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

  /// Injectable time source for testable search-cache TTL.
  final DateTime Function() _clock;

  /// Write metadata: fresh id per operation, collapsed to one push per employee.
  String _newSeriesOpId() => const Uuid().v4();

  // Bounded LRU cache of search results; singleton repository enables reuse across autoDispose providers.
  static const int _searchCacheMax = 50;

  /// TTL for cached results; local writes invalidate immediately, remote writes covered by TTL.
  static const Duration _searchCacheTtl = Duration(minutes: 2);

  final Map<String, _CachedHistorySearch> _searchCache = {};

  // One scan window serves all queries within TTL, avoiding per-query re-reads.
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

  // Drop caches on local write to avoid stale results or dangling references.
  void _invalidateSearchCache() {
    _searchCache.clear();
    _scanWindow = null;
    _localWrites.add(null);
  }

  // Broadcast stream for self-invalidation on local writes.
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
    // Exclude pictures from surviving doc to avoid stale-snapshot clobbering.
    final opId = _newSeriesOpId();
    final batch = _appointments.firestore.batch()
      ..update(_appointments.doc(updated.id), {
        ..._toFirestoreMap(updated, includePictures: false),
        'seriesOpId': opId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    for (final id in deleteIds) {
      batch.delete(_appointments.doc(id));
    }
    for (final copy in copies) {
      batch.set(_appointments.doc(copy.id), {
        ..._toFirestoreMap(copy),
        'seriesOpId': opId,
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
    // Never rewrite pictures to avoid clobbering concurrent background uploads.
    await _appointments.doc(appointment.id).update({
      ..._toFirestoreMap(appointment, includePictures: false),
      'seriesOpId': _newSeriesOpId(),
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
    // Transaction handles concurrent sibling deletes gracefully; one op-id collapses notifications.
    final opId = _newSeriesOpId();
    await _appointments.firestore.runTransaction((txn) async {
      final refs = [for (final r in records) _appointments.doc(r.id)];
      final snaps = await Future.wait([for (final ref in refs) txn.get(ref)]);
      for (var i = 0; i < records.length; i++) {
        if (!snaps[i].exists) continue;
        // Exclude pictures so each sibling keeps its own photos.
        txn.update(refs[i], {
          ..._toFirestoreMap(records[i], includePictures: false),
          'seriesOpId': opId,
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
    // Use arrayUnion so concurrent uploads only append their own photos, never erase.
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

  // Valid statuses: pending → in_progress → done, plus cancelled.
  static const _allowedStatuses = {
    'pending',
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
    // Stamp op-id only on cancel to keep separate cancels distinct; done is employee-writable.
    await _appointments.doc(id).update({
      'status': trimmed,
      if (trimmed == 'cancelled') 'seriesOpId': _newSeriesOpId(),
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
    // Newest-first, cursor-paged with doc-id tiebreaker for stable pagination.
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

  @override
  Future<List<AppointmentRecord>> fetchClientHistory({
    required String clientId,
    int limit = 50,
  }) async {
    if (clientId.isEmpty) return const [];
    // Filter on clientId alone (single-field index); sort newest-first in Dart.
    final snapshot = await _appointments
        .where('clientId', isEqualTo: clientId)
        .limit(limit)
        .get();
    return snapshot.docs
        .map((doc) => AppointmentRecord.fromMap(doc.id, doc.data()))
        .toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
  }

  static const List<String> _historyStatuses = ['done', 'cancelled'];

  // Bounded scan window for history search (mirrors clients search).
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

    // Parsing + matching is CPU work; run off UI thread via compute.
    final matches = await compute(
      matchHistoryDocs,
      HistorySearchScan(docs: window.docs, query: q),
    );
    _cacheSearch(cacheKey, matches);
    return matches;
  }

  /// Newest-first window of terminal visits; cached and shared by successive queries.
  Future<_CachedHistoryScanWindow?> _historyScanWindow() async {
    final cached = _scanWindow;
    if (cached != null && _isFresh(cached.fetchedAt)) return cached;

    final QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      // Same query shape as fetchHistoryPage; uses existing composite index.
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

    // Batch queries by 30-ID limit and execute in parallel.
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
        // Filter terminal visits here, not in query (Firestore can't combine with arrayContainsAny).
        final status = (data['status'] ?? '').toString().toLowerCase();
        if (_terminalStatuses.contains(status)) continue;
        final empIds = data['employeeIds'] as List<dynamic>? ?? const [];
        busyIds.addAll(empIds.whereType<String>());
      }
    }

    return candidates.where((e) => busyIds.contains(e.id)).toList();
  }

  // Terminal statuses; 'completed' is legacy alias for 'done'.
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

/// Raw doc for isolate-safe compute payload (Firestore handles don't cross boundaries).
typedef RawHistoryDoc = ({String id, Map<String, dynamic> data});

/// `compute` payload for [matchHistoryDocs].
class HistorySearchScan {
  const HistorySearchScan({required this.docs, required this.query});

  final List<RawHistoryDoc> docs;
  final String query;
}

/// Parse and return matching visits by client/employee name or phone digits.
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

// Auth-propagation delay workaround: retry on permission-denied (same guard as login).
bool _isAuthPropagationDenied(Object error) =>
    error is FirebaseException && error.code == 'permission-denied';
