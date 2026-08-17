// Mocktail fakes must subclass cloud_firestore's sealed query/snapshot types.
// ignore_for_file: subtype_of_sealed_class

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/features/calendar/data/firebase_appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _MockCollection extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class _MockDoc extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class _MockBatch extends Mock implements WriteBatch {}

class _MockTransaction extends Mock implements Transaction {}

class _MockDocSnap extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {}

class _MockQuery extends Mock implements Query<Map<String, dynamic>> {}

class _MockQuerySnapshot extends Mock
    implements QuerySnapshot<Map<String, dynamic>> {}

class _MockQueryDocSnap extends Mock
    implements QueryDocumentSnapshot<Map<String, dynamic>> {}

class _FakeDoc extends Fake
    implements DocumentReference<Map<String, dynamic>> {}

class _FakeSetOptions extends Fake implements SetOptions {}

// Declared as a top-level function (not a closure) so its runtime type exactly
// matches mocktail's `any()` for the repo's transaction handler.
Future<Null> _fallbackHandler(Transaction _) async => null;

AppointmentRecord _record({String? id = 'a1'}) => AppointmentRecord(
  id: id,
  title: 'Leak',
  startTime: DateTime(2026, 6, 24, 9),
  endTime: DateTime(2026, 6, 24, 10),
);

const _photo = AppointmentImage(
  storagePath: 'appointments/a1/images/1754835600000_p.jpg',
);

/// One public write method, and how to call it.
typedef _WriteCase = ({
  String method,
  Future<void> Function(FirebaseAppointmentsRepository) run,
});

/// Every public method of the repository that mutates Firestore.
///
/// Kept honest by the `covers every mutating method in the source` test below —
/// a new write method is a compile-free, test-free way to break history search
/// otherwise, and the symptom is a search result opening a detail view for a
/// document that no longer exists.
final List<_WriteCase> _writeCases = [
  (method: 'addAppointment', run: (r) => r.addAppointment(_record())),
  (method: 'addAppointments', run: (r) => r.addAppointments([_record()])),
  (
    method: 'rewriteSeries',
    run: (r) => r.rewriteSeries(
      updated: _record(),
      deleteIds: const ['a2'],
      copies: [_record(id: 'a3')],
    ),
  ),
  (method: 'updateAppointment', run: (r) => r.updateAppointment(_record())),
  (
    method: 'updateAppointments',
    run: (r) => r.updateAppointments([_record()]),
  ),
  (
    method: 'appendAppointmentPictures',
    run: (r) => r.appendAppointmentPictures('a1', const [_photo]),
  ),
  (
    method: 'removeAppointmentPictures',
    run: (r) => r.removeAppointmentPictures('a1', const [_photo]),
  ),
  (
    method: 'updateAppointmentStatus',
    run: (r) => r.updateAppointmentStatus(id: 'a1', status: 'done'),
  ),
  (method: 'deleteAppointment', run: (r) => r.deleteAppointment('a1')),
  (
    method: 'deleteAppointments',
    run: (r) => r.deleteAppointments(const ['a1']),
  ),
];

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeDoc());
    registerFallbackValue(_FakeSetOptions());
    registerFallbackValue(<String, dynamic>{});
    // The fallback and the stub both need to match the transaction handler's
    // reified Null return type.
    registerFallbackValue(_fallbackHandler);
  });

  late _MockFirestore firestore;
  late _MockCollection appointments;
  late _MockDoc parentDoc;
  late _MockCollection images;
  late _MockBatch batch;
  late _MockTransaction txn;
  late _MockQuery query;
  late _MockQuerySnapshot snapshot;

  setUp(() {
    firestore = _MockFirestore();
    appointments = _MockCollection();
    parentDoc = _MockDoc();
    images = _MockCollection();
    batch = _MockBatch();
    txn = _MockTransaction();
    query = _MockQuery();
    snapshot = _MockQuerySnapshot();

    when(() => firestore.collection('appointments')).thenReturn(appointments);
    when(() => appointments.firestore).thenReturn(firestore);
    when(() => appointments.doc(any())).thenReturn(parentDoc);
    when(() => parentDoc.collection('images')).thenReturn(images);
    when(() => images.doc(any())).thenReturn(_MockDoc());
    when(() => parentDoc.update(any())).thenAnswer((_) async {});

    when(firestore.batch).thenReturn(batch);
    when(() => batch.set<Map<String, dynamic>>(any(), any())).thenReturn(null);
    when(
      () => batch.set<Map<String, dynamic>>(any(), any(), any()),
    ).thenReturn(null);
    when(() => batch.update(any(), any())).thenReturn(null);
    when(() => batch.delete(any())).thenReturn(null);
    when(batch.commit).thenAnswer((_) async {});

    final txnSnap = _MockDocSnap();
    when(() => txnSnap.exists).thenReturn(true);
    when(() => txn.get<Map<String, dynamic>>(any())).thenAnswer(
      (_) async => txnSnap,
    );
    when(() => txn.update(any(), any())).thenReturn(txn);
    when(() => firestore.runTransaction<Null>(any())).thenAnswer((
      invocation,
    ) async {
      final handler =
          invocation.positionalArguments.first
              as Future<void> Function(Transaction);
      await handler(txn);
    });

    // The history-search scan window.
    when(
      () => appointments.where('status', whereIn: any(named: 'whereIn')),
    ).thenReturn(query);
    when(
      () => query.orderBy(any(), descending: any(named: 'descending')),
    ).thenReturn(query);
    when(() => query.limit(any())).thenReturn(query);
    when(() => query.get()).thenAnswer((_) async => snapshot);

    // Built before `docs` is stubbed — mocktail forbids calling `when` while
    // another stub is being defined.
    final hit = _MockQueryDocSnap();
    when(() => hit.id).thenReturn('a1');
    when(hit.data).thenReturn({'clientName': 'Sophie Tremblay'});
    when(() => snapshot.docs).thenReturn([hit]);
  });

  FirebaseAppointmentsRepository repo() =>
      FirebaseAppointmentsRepository(firestore);

  group('a local write drops the history-search cache', () {
    // The repository is a long-lived singleton, so the cache outlives every
    // autoDispose provider reading it. A write method that forgets
    // `_invalidateSearchCache()` leaves history search serving a DELETED
    // appointment for the whole TTL — tapping the result opens a detail view
    // for a document that no longer exists, with no error anywhere.

    test(
      'control: without a write, the second search is served from cache',
      () async {
        // Without this, every case below would pass against a repository that
        // simply never caches, and the invalidation would be unasserted again.
        final r = repo();
        await r.searchHistory('sophie');
        await r.searchHistory('sophie');

        verify(() => query.get()).called(1);
      },
    );

    for (final c in _writeCases) {
      test('${c.method} forces the next search to re-query', () async {
        final r = repo();
        await r.searchHistory('sophie');
        await c.run(r);
        await r.searchHistory('sophie');

        verify(() => query.get()).called(2);
      });
    }
  });

  group('the table above covers the repository', () {
    // Dart has no reflection here, so the guard is the source itself: the same
    // read-the-file posture `text_limits_test.dart` uses against
    // `firestore.rules`. Without it, adding a write method is invisible to
    // every test in this directory.

    /// Method name -> body, for the members of `FirebaseAppointmentsRepository`,
    /// with comments stripped so a token quoted in prose can't count as code.
    Map<String, String> repositoryMembers() {
      final source = File(
        'lib/features/calendar/data/firebase_appointments_repository.dart',
      ).readAsStringSync();
      final code = source
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .toList();
      // A member declaration sits at exactly two spaces of indent and names its
      // return type; a statement inside a body is indented further.
      final decl = RegExp(r'^  (?:static\s+)?[A-Za-z_][\w<>?,\[\] ]*\s(\w+)\(');

      final members = <String, StringBuffer>{};
      StringBuffer? current;
      for (final line in code) {
        final match = decl.firstMatch(line);
        if (match != null) {
          current = members[match.group(1)!] = StringBuffer();
        }
        current?.writeln(line);
      }
      return {
        for (final e in members.entries) e.key: e.value.toString(),
      };
    }

    /// Anything that changes a document. `runTransaction` counts on its own —
    /// its writes happen through the handler's `txn`, not this body.
    bool mutates(String body) => const [
      '.set(',
      '.update(',
      '.delete(',
      'batch.commit',
      'runTransaction',
    ].any(body.contains);

    late final members = repositoryMembers();
    late final mutating = members.entries
        .where((e) => !e.key.startsWith('_') && mutates(e.value))
        .map((e) => e.key);

    test('parsed the source at all', () {
      // A regex that silently matched nothing would make both tests below
      // vacuous, which is the failure mode this whole group exists to prevent.
      expect(members.keys, containsAll(['searchHistory', 'findBusyEmployees']));
      expect(mutating, isNotEmpty);
    });

    test('every mutating public method is in the table', () {
      expect(
        mutating,
        everyElement(isIn(_writeCases.map((c) => c.method))),
        reason:
            'a new write method must be added to _writeCases, or nothing '
            'checks that it drops the history-search cache',
      );
    });

    test('every mutating public method calls _invalidateSearchCache()', () {
      // The static half of the same rule: it fails on the method that forgot
      // the call, rather than only on the ones somebody remembered to add to
      // the table.
      for (final name in mutating) {
        expect(
          members[name],
          contains('_invalidateSearchCache()'),
          reason: '$name mutates Firestore without invalidating the cache',
        );
      }
    });
  });
}
