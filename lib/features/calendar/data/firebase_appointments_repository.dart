import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/clients/domain/policies/client_search_policy.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

class FirebaseAppointmentsRepository implements AppointmentsRepository {
  FirebaseAppointmentsRepository(FirebaseFirestore firestore)
    : _appointments = firestore.collection('appointments');

  final CollectionReference<Map<String, dynamic>> _appointments;

  // Bounded LRU of recent history-search results. The repository is a
  // long-lived singleton (it outlives the autoDispose historySearchProvider),
  // so re-searching a term reuses the result instead of re-reading up to
  // _historySearchScanLimit docs. Mirrors FirebaseClientsRepository.
  static const int _searchCacheMax = 50;
  final Map<String, List<AppointmentRecord>> _searchCache = {};

  void _cacheSearch(String key, List<AppointmentRecord> results) {
    _searchCache.remove(key);
    if (_searchCache.length >= _searchCacheMax) {
      _searchCache.remove(_searchCache.keys.first);
    }
    _searchCache[key] = results;
  }

  // Any write can change which docs a query matches, so drop the cache rather
  // than serve stale results — or list a just-deleted appointment that opens a
  // detail view for a doc that no longer exists.
  void _invalidateSearchCache() => _searchCache.clear();

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
    final batch = _appointments.firestore.batch()
      ..update(_appointments.doc(updated.id), {
        ..._toFirestoreMap(updated),
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
    await _appointments.doc(appointment.id).update({
      ..._toFirestoreMap(appointment),
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
        txn.update(refs[i], {
          ..._toFirestoreMap(records[i]),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
    _invalidateSearchCache();
  }

  @override
  Future<void> updateAppointmentPictures(
    String id,
    List<AppointmentImage> pictures,
  ) async {
    await _appointments.doc(id).update({
      'pictures': pictures.map(_imageToFirestoreMap).toList(),
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
    return _appointments
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
        );
  }

  @override
  Future<List<AppointmentRecord>> fetchHistoryPage({
    required int limit,
    AppointmentRecord? after,
  }) async {
    // Newest-first, server-ordered + cursor-paged so the most recent history
    // is always returned (the old limit(500) had no orderBy, so it kept an
    // arbitrary doc-id slice and could drop recent visits past 500). Served by
    // the existing `appointments (status ASC, startTime ASC)` composite index,
    // scanned in reverse for the descending order.
    var query = _appointments
        .where('status', whereIn: _historyStatuses)
        .orderBy('startTime', descending: true);
    final afterId = after?.id;
    if (afterId != null) {
      final afterDoc = await _appointments.doc(afterId).get();
      if (afterDoc.exists) query = query.startAfterDocument(afterDoc);
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
    if (cached != null) {
      _cacheSearch(cacheKey, cached); // mark most-recently-used
      return cached;
    }

    final normalizedQuery = ClientSearchPolicy.normalize(q);
    final queryDigits = ClientSearchPolicy.digitsOnly(q);

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
      debugPrint('[FirebaseAppointmentsRepository] searchHistory failed: $e');
      debugPrintStack(stackTrace: st);
      return const [];
    }

    final matches = <AppointmentRecord>[];
    for (final doc in snapshot.docs) {
      final a = AppointmentRecord.fromMap(doc.id, doc.data());
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
    _cacheSearch(cacheKey, matches);
    return matches;
  }

  @override
  Stream<List<AppointmentRecord>> watchForEmployeeInRange(
    String employeeId,
    AppointmentDateRange range,
  ) {
    return _appointments
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
        final empIds = doc.data()['employeeIds'] as List<dynamic>? ?? const [];
        busyIds.addAll(empIds.whereType<String>());
      }
    }

    return candidates.where((e) => busyIds.contains(e.id)).toList();
  }

  Map<String, dynamic> _toFirestoreMap(AppointmentRecord appointment) {
    final base = Map<String, dynamic>.from(appointment.toMap());
    base['startTime'] = Timestamp.fromDate(appointment.startTime);
    base['endTime'] = Timestamp.fromDate(appointment.endTime);
    base['pictures'] = appointment.pictures.map(_imageToFirestoreMap).toList();
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
