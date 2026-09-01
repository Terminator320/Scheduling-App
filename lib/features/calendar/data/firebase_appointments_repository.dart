import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show compute;

import 'package:scheduling/core/data/paged_scan.dart';
import 'package:scheduling/core/data/search_result_cache.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/utils/firestore_parsing.dart';
import 'package:scheduling/core/utils/retry.dart';
import 'package:scheduling/features/calendar/data/appointment_images_store.dart';
import 'package:scheduling/features/calendar/domain/appointment_status_values.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/assignee_availability.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/domain/models/repeat_interval.dart';
import 'package:scheduling/features/calendar/domain/policies/history_search_policy.dart';
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
       _clock = clock ?? DateTime.now {
    _images = AppointmentImagesStore(
      appointments: _appointments,
      logger: _logger,
    );
  }

  final CollectionReference<Map<String, dynamic>> _appointments;
  final AppLogger _logger;

  /// The photo half — the `appointments/{id}/images` subcollection. A
  /// collaborator because the migration's contract step rewrote that whole
  /// surface; see [AppointmentImagesStore].
  late final AppointmentImagesStore _images;

  /// Lets tests inject a fake clock so the search-cache TTL is testable.
  final DateTime Function() _clock;

  /// Generates a fresh id for each write op, so all the notifications a
  /// single write triggers collapse into one per employee.
  String _newSeriesOpId() => const Uuid().v4();

  static const int _historySearchPageSize = 500;

  /// Ceiling on the live business-wide range listeners. Paging fixed the silent
  /// truncation these used to have, but a listener still has to be bounded: it
  /// is re-established per month page and held open by the calendar, the day
  /// route, the drawer badge, the roster reducer and the dashboard at once.
  static const int _rangeStreamLimit = 3000;

  /// Ceiling on the paged history-search scan window. The archive is only
  /// pruned at the 2-year retention mark, so without this the first committed
  /// keystroke walks every terminal appointment the business has ever had.
  static const int _historySearchScanLimit = 5000;

  /// Ceiling on one client's paged job history.
  static const int _clientHistoryScanLimit = 1000;

  /// Page size for that scan. Kept off the caller's `limit` so a busy client
  /// costs two round-trips to reach the ceiling, not twenty.
  static const int _clientHistoryPageSize = 500;

  /// Bounded LRU of recent results. The dials (50 entries, 2 minutes) live on
  /// [SearchResultCache], which the clients repository shares — they were two
  /// byte-identical copies of one cost decision.
  late final SearchResultCache<AppointmentRecord> _searchCache =
      SearchResultCache(clock: _clock);

  _CachedHistoryScanWindow? _scanWindow;

  bool _isFresh(DateTime fetchedAt) => _searchCache.isFresh(fetchedAt);

  /// Merges locally-written appointments into the history scan window instead
  /// of dropping it.
  ///
  /// **Every appointment-write method must call this or [_notifyLocalWrite].**
  /// It replaced `_invalidateSearchCache`, which threw the window away: a new
  /// write path that calls neither serves stale history-search results,
  /// including a just-deleted appointment that opens a detail view for a doc
  /// that no longer exists.
  ///
  /// [changed] maps doc id to the fields just written, or null for a delete.
  /// The window is the full paged terminal-status archive capped at
  /// [_historySearchScanLimit] (5000), and NINE write paths used to discard it
  /// outright — so an admin who searched History, opened a result and marked
  /// it complete re-paged the whole archive behind the sheet: thousands of
  /// billed reads and four sequential round trips for a one-field write, then
  /// `compute` marshalling every raw map across the isolate boundary again. It
  /// grows with the archive. The clients repository already solved this with
  /// its own `_patchWindow`; this is that treatment for appointments.
  ///
  /// A doc whose status is no longer terminal is REMOVED rather than merged —
  /// the window query is `status whereIn terminalStatusQueryValues`, so a job
  /// created as `pending`, or reopened, does not belong in it. That is also
  /// what makes `addAppointments` safe to route through here.
  ///
  /// ORDER is preserved, not appended to: the window is `startTime` DESC and
  /// `searchHistory` returns it unsorted, so a re-appended doc would surface
  /// out of order in the results list.
  void _patchWindow(Map<String, Map<String, dynamic>?> changed) {
    _searchCache.clear();
    final window = _scanWindow;
    if (window == null || !_isFresh(window.fetchedAt)) {
      _scanWindow = null;
      if (!_localWrites.isClosed) _localWrites.add(null);
      return;
    }

    final docs = <RawHistoryDoc>[];
    final merged = <String>{};
    for (final doc in window.docs) {
      if (!changed.containsKey(doc.id)) {
        docs.add(doc);
        continue;
      }
      merged.add(doc.id);
      final next = _windowDoc(doc.data, changed[doc.id]);
      if (next != null) docs.add((id: doc.id, data: next));
    }
    // A job the window has never seen (a create, or one that just became
    // terminal) goes in at its own date rather than at the end.
    for (final entry in changed.entries) {
      if (merged.contains(entry.key)) continue;
      final next = _windowDoc(const {}, entry.value);
      if (next == null) continue;
      docs.insert(_insertIndexFor(docs, next), (id: entry.key, data: next));
    }
    _scanWindow = _CachedHistoryScanWindow(docs, window.fetchedAt);
    if (!_localWrites.isClosed) _localWrites.add(null);
  }

  /// The window row [patch] leaves behind, or null when the doc drops out.
  ///
  /// `FieldValue` sentinels are stripped: they are write instructions, not
  /// values, and storing one would make `firestoreDateTime` read the field as
  /// absent on the next `fromMap`. The previous value stays instead, at most
  /// [SearchResultCache.ttl] stale.
  static Map<String, dynamic>? _windowDoc(
    Map<String, dynamic> previous,
    Map<String, dynamic>? patch,
  ) {
    if (patch == null) return null;
    final next = {
      ...previous,
      for (final e in patch.entries)
        if (e.value is! FieldValue) e.key: e.value,
    };
    return isTerminalStatusRaw((next['status'] ?? '').toString()) ? next : null;
  }

  /// Where [doc] belongs in a `startTime` DESC window.
  static int _insertIndexFor(List<RawHistoryDoc> docs, Map<String, dynamic> doc) {
    final at = firestoreDateTime(doc['startTime']);
    if (at == null) return docs.length;
    for (var i = 0; i < docs.length; i++) {
      final other = firestoreDateTime(docs[i].data['startTime']);
      if (other == null || other.isBefore(at)) return i;
    }
    return docs.length;
  }

  /// Wakes `onLocalWrite` without touching the search cache or the window.
  ///
  /// For a write that provably changes no field `matchHistoryDocs` reads —
  /// the photo paths, which only ever touch the `images` subcollection and the
  /// parent's `updatedAt`. The client job-history section still has to refetch
  /// (the card's photo indicator reads `pictureCount`), which is what the poke
  /// is for.
  void _notifyLocalWrite() {
    if (!_localWrites.isClosed) _localWrites.add(null);
  }

  /// Unlike [_patchWindow] this does NOT poke `_localWrites`. Its callers are
  /// signing the user out, and waking every `onLocalWrite` listener on the way
  /// would refetch against a credential that is about to be revoked.
  @override
  void clearCaches() {
    _searchCache.clear();
    _scanWindow = null;
  }

  final StreamController<void> _localWrites = StreamController.broadcast();

  @override
  Stream<void> get onLocalWrite => _localWrites.stream;

  void dispose() {
    unawaited(_localWrites.close());
  }

  @override
  String newDocId() => _appointments.doc().id;

  @override
  Future<AppointmentRecord?> getAppointmentById(String id) async {
    final doc = await _appointments.doc(id).get();
    if (!doc.exists) return null;
    return _recordFrom(doc.id, doc.data() ?? {});
  }

  AppointmentRecord _recordFrom(String id, Map<String, dynamic> data) {
    if (data['startTime'] == null || data['endTime'] == null) {
      _logger.breadcrumb(
        'APPT-LOAD $id has no startTime/endTime; substituting now',
      );
    }
    return AppointmentRecord.fromMap(id, data);
  }

  @override
  Future<int> countFutureAssignments(String employeeId) async {
    final now = DateTime.now();
    final snapshot = await _appointments
        .where('employeeIds', arrayContains: employeeId)
        .where('endTime', isGreaterThanOrEqualTo: Timestamp.fromDate(now))
        .limit(_futureAssignmentScanLimit)
        .get();
    if (snapshot.docs.length >= _futureAssignmentScanLimit) {
      _logger.warn(
        'APPT-COUNT future-assignment query hit the '
        '$_futureAssignmentScanLimit-doc cap - the caption is understating',
      );
    }
    return snapshot.docs
        .map((d) => AppointmentRecord.fromMap(d.id, d.data()))
        .where((a) => !isTerminalStatusRaw(a.status))
        .length;
  }

  @override
  Future<void> addAppointment(AppointmentRecord appointment) =>
      addAppointments([appointment]);

  @override
  Future<void> addAppointments(List<AppointmentRecord> appointments) async {
    final batch = _appointments.firestore.batch();
    final written = <String, Map<String, dynamic>?>{};
    for (final appointment in appointments) {
      final doc = appointment.id == null
          ? _appointments.doc()
          : _appointments.doc(appointment.id);
      written[doc.id] = _toFirestoreMap(appointment);
      batch.set(doc, {
        ..._toFirestoreMap(appointment),
        // The one client write of this counter the rules allow, and the reason
        // "absent" is not a state anything downstream has to interpret: the
        // recount trigger only fires on a photo write, so a job created without
        // it would read as count-unknown until its first photo. It backs the
        // card's photo indicator only — never gate a subcollection read on it
        // (see `_loadStoredPictures`).
        'pictureCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    _patchWindow(written);
  }

  @override
  Future<List<AppointmentRecord>> getSeries(String seriesId) async {
    final snapshot = await _appointments
        .where('seriesId', isEqualTo: seriesId)
        .limit(_seriesScanLimit)
        .get();
    if (snapshot.docs.length >= _seriesScanLimit) {
      _logger.warn(
        'APPT-LOAD series $seriesId hit the '
        '$_seriesScanLimit-doc cap - siblings beyond it were not loaded',
      );
    }
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
    final opId = _newSeriesOpId();
    final batch = _appointments.firestore.batch()
      ..update(_appointments.doc(updated.id), {
        ..._toFirestoreMap(updated),
        'seriesOpId': opId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    final written = <String, Map<String, dynamic>?>{
      updated.id!: _toFirestoreMap(updated),
      for (final id in deleteIds) id: null,
      for (final copy in copies) copy.id!: _toFirestoreMap(copy),
    };
    for (final id in deleteIds) {
      batch.delete(_appointments.doc(id));
    }
    for (final copy in copies) {
      batch.set(_appointments.doc(copy.id), {
        ..._toFirestoreMap(copy),
        // A copied occurrence is a new document — same reasoning as
        // `addAppointments`, and photos never come along with one.
        'pictureCount': 0,
        'seriesOpId': opId,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    _patchWindow(written);
  }

  @override
  Future<void> updateAppointment(AppointmentRecord appointment) async {
    if (appointment.id == null) return;
    await _appointments.doc(appointment.id).update({
      ..._toFirestoreMap(appointment),
      'seriesOpId': _newSeriesOpId(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _patchWindow({appointment.id!: _toFirestoreMap(appointment)});
  }

  @override
  Future<void> updateAppointments(List<AppointmentRecord> appointments) async {
    final records = [
      for (final a in appointments)
        if (a.id != null) a,
    ];
    if (records.isEmpty) return;
    final opId = _newSeriesOpId();
    final written = <String, Map<String, dynamic>?>{};
    await _appointments.firestore.runTransaction((txn) async {
      final refs = [for (final r in records) _appointments.doc(r.id)];
      final snaps = await Future.wait([for (final ref in refs) txn.get(ref)]);
      // Rebuilt per attempt: a transaction can re-run, and a set carried over
      // from an abandoned attempt would name docs this commit never touched.
      written.clear();
      for (var i = 0; i < records.length; i++) {
        if (!snaps[i].exists) continue;
        written[records[i].id!] = _toFirestoreMap(records[i]);
        txn.update(refs[i], {
          ..._toFirestoreMap(records[i]),
          'seriesOpId': opId,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
    _patchWindow(written);
  }

  @override
  Future<void> appendAppointmentPictures(
    String id,
    List<AppointmentImage> pictures,
  ) async {
    await _images.append(id, pictures);
    _notifyLocalWrite();
  }

  @override
  Future<void> removeAppointmentPictures(
    String id,
    List<AppointmentImage> pictures,
  ) async {
    await _images.remove(id, pictures);
    _notifyLocalWrite();
  }

  @override
  Future<List<AppointmentImage>> fetchAppointmentPictures(String id) =>
      _images.fetch(id);

  static const _allowedStatuses = {
    'pending',
    'in_progress',
    'done',
    'cancelled',
  };

  // NOT delegated to `updateAppointmentStatuses([id])`, though the bodies look
  // duplicated: this writes the document DIRECTLY while the plural commits a
  // WriteBatch. The single write is the employee mark-done path, which the
  // rules gate with `affectedKeys().hasOnly(['status', 'updatedAt'])` — the
  // most security-sensitive write in the app — and it is pinned field-by-field
  // by `firebase_appointments_repository_status_test.dart`. Collapsing the two
  // buys ~18 lines and pays for them by routing that path through a different
  // Firestore mechanism.
  @override
  Future<void> updateFieldNotes({
    required String id,
    required String notes,
  }) async {
    // EXACTLY the two keys the assignee rules branch allows. Anything else —
    // including a `seriesOpId`, which every other write here mints — is
    // refused as an opaque `permission-denied`.
    await _appointments.doc(id).update({
      'fieldNotes': notes,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _patchWindow({
      id: {'fieldNotes': notes},
    });
  }

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
      if (trimmed == 'cancelled') 'seriesOpId': _newSeriesOpId(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _patchWindow({id: {'status': trimmed}});
  }

  @override
  Future<void> updateAppointmentStatuses({
    required List<String> ids,
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
    if (ids.isEmpty) return;
    // ONE shared op id across the batch, so `claimSeriesNotice` collapses the
    // whole run into a single push instead of one per day — the same claim
    // `updateAppointments` and `rewriteSeries` make. Minted for a cancel only,
    // matching `updateAppointmentStatus`: the employee mark-done rule is
    // `affectedKeys().hasOnly(['status', 'updatedAt'])`, and an extra key there
    // is rejected as `permission-denied`.
    final opId = _newSeriesOpId();
    final batch = _appointments.firestore.batch();
    for (final id in ids) {
      batch.update(_appointments.doc(id), {
        'status': trimmed,
        if (trimmed == 'cancelled') 'seriesOpId': opId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    _patchWindow({for (final id in ids) id: {'status': trimmed}});
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
    _patchWindow({for (final id in ids) id: null});
  }

  List<AppointmentRecord> _mapRangeSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    if (snapshot.docs.length >= _rangeStreamLimit) {
      _logger.warn(
        'APPT-LOAD range query hit the $_rangeStreamLimit-doc cap - '
        'appointments beyond it are not shown',
      );
    }
    return snapshot.docs
        .map((doc) => AppointmentRecord.fromMap(doc.id, doc.data()))
        .toList();
  }

  Query<Map<String, dynamic>> _rangeQuery(
    AppointmentDateRange range, {
    String? employeeId,
  }) {
    Query<Map<String, dynamic>> query = _appointments;
    if (employeeId != null) {
      query = query.where('employeeIds', arrayContains: employeeId);
    }
    return query
        .where(
          'startTime',
          isGreaterThanOrEqualTo: Timestamp.fromDate(range.fetchStart),
        )
        .where('startTime', isLessThan: Timestamp.fromDate(range.end))
        .orderBy('startTime')
        .limit(_rangeStreamLimit);
  }

  @override
  Stream<List<AppointmentRecord>> watchInRange(AppointmentDateRange range) {
    return retryStream(
      () => _rangeQuery(range).snapshots().map(_mapRangeSnapshot),
    );
  }

  @override
  Future<List<AppointmentRecord>> fetchInRange(
    AppointmentDateRange range,
  ) async {
    final snapshot = await retryAsync(() => _rangeQuery(range).get());
    return _mapRangeSnapshot(snapshot);
  }

  @override
  Future<List<AppointmentRecord>> fetchHistoryPage({
    required int limit,
    AppointmentRecord? after,
  }) async {
    var query = _appointments
        .where('status', whereIn: terminalStatusQueryValues)
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
    int limit = _clientHistoryPageSize,
  }) async {
    if (clientId.isEmpty) return const [];
    final docs = await pageToCap(
      _appointments
          .where('clientId', isEqualTo: clientId)
          .orderBy('startTime', descending: true),
      pageSize: limit,
      cap: _clientHistoryScanLimit,
      onCapReached: () => _logger.warn(
        'APPT-LOAD client history hit the $_clientHistoryScanLimit-doc cap - '
        'older visits are not listed',
      ),
    );
    // A multi-day run is ONE visit stored as one document per work day, so
    // listing every document rendered a Monday-to-Friday job as five identical
    // rows — and burned five of the section's 50-row render bound. Day 1
    // carries the run and is the row worth showing; the card already says
    // "Day 1 of 5". Filtered HERE rather than in the query: only a run member
    // stores `dayIndex`, so a server-side inequality would need a second
    // composite AND would drop every document that predates the field.
    return docs
        .map((doc) => _recordFrom(doc.id, doc.data()))
        .where((record) => record.dayIndex <= 1)
        .toList();
  }

  static const int _futureAssignmentScanLimit = 200;
  static const int _seriesScanLimit = RepeatInterval.maxOccurrences + 1;
  static const int _conflictScanLimit = 1000;

  @override
  Future<List<AppointmentRecord>> searchHistory(String query) async {
    final q = query.trim();
    if (!ClientSearchPolicy.shouldSearch(q)) return const [];

    final cacheKey = ClientSearchPolicy.cacheKey(q);
    final cached = _searchCache.read(cacheKey);
    if (cached != null) return cached;

    final window = await _historyScanWindow();
    if (window == null) return const [];

    final matches = await compute(
      matchHistoryDocs,
      HistorySearchScan(docs: window.docs, query: q),
    );
    _searchCache.write(cacheKey, matches);
    return matches;
  }

  Future<_CachedHistoryScanWindow?> _historyScanWindow() async {
    final cached = _scanWindow;
    if (cached != null && _isFresh(cached.fetchedAt)) return cached;
    _scanWindow = null;

    try {
      final scanned = await pageToCap(
        _appointments
            .where('status', whereIn: terminalStatusQueryValues)
            .orderBy('startTime', descending: true),
        pageSize: _historySearchPageSize,
        cap: _historySearchScanLimit,
        onCapReached: () => _logger.warn(
          'HIST-SEARCH scan window hit the $_historySearchScanLimit-doc cap - '
          'older jobs are not searchable',
        ),
      );
      final docs = <RawHistoryDoc>[
        for (final doc in scanned) (id: doc.id, data: doc.data()),
      ];
      final window = _CachedHistoryScanWindow(docs, _clock());
      _scanWindow = window;
      return window;
    } on FirebaseException catch (e, st) {
      _logger.warn('HIST-SEARCH searchHistory failed', e, st);
      return null;
    }
  }

  @override
  Stream<List<AppointmentRecord>> watchForEmployeeInRange(
    String employeeId,
    AppointmentDateRange range,
  ) {
    return retryStream(
      () => _rangeQuery(range, employeeId: employeeId).snapshots().map(
        _mapRangeSnapshot,
      ),
    );
  }

  @override
  Future<List<EmployeeRecord>> findBusyEmployees({
    required List<EmployeeRecord> candidates,
    required DateTime start,
    required DateTime end,
    String? excludeAppointmentId,
  }) async {
    if (candidates.isEmpty) return const [];

    // The busy PEOPLE are the clashing records' assignees: same query, same
    // rule, one owner. Spelled inline here once, and the two answers drifting
    // is exactly the bug that would leave the picker dimming someone this
    // prompt then waves through.
    final clashes = await findClashingAppointments(
      employeeIds: candidates.map((e) => e.id).toList(),
      start: start,
      end: end,
      excludeAppointmentId: excludeAppointmentId,
    );
    final busyIds = {for (final a in clashes) ...a.employeeIds};
    return candidates.where((e) => busyIds.contains(e.id)).toList();
  }

  @override
  Future<List<AppointmentRecord>> findClashingAppointments({
    required List<String> employeeIds,
    required DateTime start,
    required DateTime end,
    String? excludeAppointmentId,
    bool clientJobsOnly = false,
  }) async {
    if (employeeIds.isEmpty) return const [];

    // Deduped by doc id: a job assigned to two people in different 30-id
    // chunks comes back from both queries.
    final found = <String, AppointmentRecord>{};
    // Read off the RAW map, which only this layer sees: the record substitutes
    // a placeholder instant for a time it could not parse, so by the time the
    // rule runs the two are indistinguishable.
    //
    // This covers an UNPARSEABLE instant, not a MISSING one, and the gap is
    // structural rather than an oversight. `_conflictSnapshots` filters on
    // `endTime`/`startTime`, and Firestore excludes a document that lacks the
    // filtered field entirely, so a row with no `endTime` never reaches this
    // loop to be classified — no bound on that field can see it. Reaching one
    // would mean dropping both bounds and scanning every appointment for the
    // crew, which is a real read cost for a row shape that does not exist:
    // verified 2026-09-01 against prod, all 76 appointments carry an
    // `endTime`. The Dart model always writes both instants, so only a
    // console-written or pre-migration row could lack one (the case
    // `_recordFrom`'s breadcrumb exists for, and `day_slice_utils.js` handles
    // server-side). If such a row is ever found, this is where it hides.
    final windowUnknownIds = <String>{};
    for (final snapshot in await _conflictSnapshots(
      employeeIds: employeeIds,
      start: start,
      end: end,
    )) {
      for (final doc in snapshot.docs) {
        final data = doc.data();
        found[doc.id] = AppointmentRecord.fromMap(doc.id, data);
        if (firestoreDateTime(data['startTime']) == null ||
            firestoreDateTime(data['endTime']) == null) {
          windowUnknownIds.add(doc.id);
        }
      }
    }

    // The overlap rule itself is the pure `clashingAppointments`, shared with
    // the picker's live reduction over the calendar's open range.
    return clashingAppointments(
      appointments: found.values,
      start: start,
      end: end,
      excludeAppointmentId: excludeAppointmentId,
      clientJobsOnly: clientJobsOnly,
      windowUnknownIds: windowUnknownIds,
    );
  }

  /// The chunked overlap prefilter both conflict reads run.
  ///
  /// `whereArrayContainsAny` caps at 30, so the ids are batched; the query is
  /// COARSE by design — it tests the raw instants, and the daily-window rule
  /// that turns those hits into real clashes is applied in Dart afterwards.
  /// One spelling, so the two readers can't drift on the constraint set, the
  /// chunk size or the cap warning.
  Future<List<QuerySnapshot<Map<String, dynamic>>>> _conflictSnapshots({
    required List<String> employeeIds,
    required DateTime start,
    required DateTime end,
  }) async {
    final queries = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
    for (var i = 0; i < employeeIds.length; i += 30) {
      final batch = employeeIds.sublist(
        i,
        i + 30 < employeeIds.length ? i + 30 : employeeIds.length,
      );
      queries.add(
        _appointments
            .where('employeeIds', arrayContainsAny: batch)
            .where('startTime', isLessThan: Timestamp.fromDate(end))
            .where('endTime', isGreaterThan: Timestamp.fromDate(start))
            .limit(_conflictScanLimit)
            .get(),
      );
    }
    final snapshots = await Future.wait(queries);
    for (final snapshot in snapshots) {
      if (snapshot.docs.length >= _conflictScanLimit) {
        _logger.warn(
          'APPT-BUSY conflict query hit the $_conflictScanLimit-doc cap - '
          'clashes beyond it are not reported',
        );
      }
    }
    return snapshots;
  }

  /// The record as Firestore fields.
  ///
  /// Photos are not here and must not come back: they live in
  /// `appointments/{id}/images`, written through [AppointmentImagesStore]. The
  /// `includePictures` flag this used to take existed only because every write
  /// path but the create had to suppress the array half; with the array gone
  /// there is nothing to suppress.
  Map<String, dynamic> _toFirestoreMap(AppointmentRecord appointment) {
    final base = Map<String, dynamic>.from(appointment.toMap());
    base['startTime'] = Timestamp.fromDate(appointment.startTime);
    base['endTime'] = Timestamp.fromDate(appointment.endTime);
    return base;
  }
}

class _CachedHistoryScanWindow {
  const _CachedHistoryScanWindow(this.docs, this.fetchedAt);

  final List<RawHistoryDoc> docs;
  final DateTime fetchedAt;
}
