// Mocktail fakes must subclass cloud_firestore's sealed query/snapshot types.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/calendar/data/appointment_field_notes_store.dart';
import 'package:scheduling/features/calendar/data/firebase_appointments_repository.dart';

class _RecordingLogger extends AppLogger {
  final warnings = <String>[];

  @override
  void warn(String message, [Object? error, StackTrace? stack]) {
    warnings.add(message);
  }
}

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _MockCollection extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class _MockDoc extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class _MockQuery extends Mock implements Query<Map<String, dynamic>> {}

class _MockQuerySnapshot extends Mock
    implements QuerySnapshot<Map<String, dynamic>> {}

class _MockDocSnap extends Mock
    implements QueryDocumentSnapshot<Map<String, dynamic>> {}

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  late _MockFirestore firestore;
  late _MockCollection appointments;
  late _MockDoc parentDoc;
  late _MockCollection notes;

  setUp(() {
    firestore = _MockFirestore();
    appointments = _MockCollection();
    parentDoc = _MockDoc();
    notes = _MockCollection();

    when(() => firestore.collection('appointments')).thenReturn(appointments);
    when(() => appointments.doc(any())).thenReturn(parentDoc);
    when(() => appointments.firestore).thenReturn(firestore);
    when(() => parentDoc.collection('fieldNotes')).thenReturn(notes);
    when(() => notes.add(any())).thenAnswer((_) async => _MockDoc());
  });

  FirebaseAppointmentsRepository repo() =>
      FirebaseAppointmentsRepository(firestore);

  Future<void> append() => repo().appendFieldNote(
    appointmentId: 'a1',
    text: 'Copper feed corroded at the elbow.',
    authorId: 'e1',
    authorName: 'Marc Tremblay',
  );

  group('appendFieldNote matches the rules contract', () {
    // firestore.rules allows create only when the payload is EXACTLY these
    // four keys with a server-stamped createdAt. Both halves were pinned
    // separately — the rules text in one test, the client map in none — so a
    // renamed or extra key failed every crew note in production with both
    // suites green.

    test('writes exactly the four keys the rules allow', () async {
      await append();

      final written =
          verify(
                () => notes.add(captureAny<Map<String, dynamic>>()),
              ).captured.single
              as Map<String, dynamic>;

      expect(written.keys.toSet(), {
        'text',
        'authorId',
        'authorName',
        'createdAt',
      });
      expect(written['text'], 'Copper feed corroded at the elbow.');
      expect(written['authorId'], 'e1');
      expect(written['authorName'], 'Marc Tremblay');
    });

    test('createdAt is a server timestamp, never a client clock', () async {
      // The rules demand `createdAt == request.time`, so a client DateTime is
      // refused outright and the note is lost.
      await append();

      final written =
          verify(
                () => notes.add(captureAny<Map<String, dynamic>>()),
              ).captured.single
              as Map<String, dynamic>;

      expect(written['createdAt'], isA<FieldValue>());
      expect(written['createdAt'], isNot(isA<DateTime>()));
    });

    test('the parent appointment is NOT written', () async {
      // Touching the parent would put this write on the assignee `allow
      // update` branches, which is exactly what the subcollection avoids.
      await append();

      verifyNever(() => parentDoc.update(any()));
      verifyNever(() => parentDoc.set(any()));
    });

    test('an empty note is not written at all', () async {
      await repo().appendFieldNote(
        appointmentId: 'a1',
        text: '   ',
        authorId: 'e1',
        authorName: 'Marc Tremblay',
      );

      verifyNever(() => notes.add(any()));
    });
  });

  group('fetch reads the NEWEST notes', () {
    late _MockQuery ordered;
    late _MockQuery limited;
    late _MockQuerySnapshot snapshot;
    late bool? capturedDescending;

    _MockDocSnap noteDoc(String id, String text) {
      final doc = _MockDocSnap();
      when(() => doc.id).thenReturn(id);
      when(doc.data).thenReturn({
        'text': text,
        'authorId': 'e1',
        'authorName': 'Marc Tremblay',
      });
      return doc;
    }

    void wire(List<_MockDocSnap> docs) {
      ordered = _MockQuery();
      limited = _MockQuery();
      snapshot = _MockQuerySnapshot();
      when(
        () => notes.orderBy(any(), descending: any(named: 'descending')),
      ).thenAnswer((invocation) {
        capturedDescending =
            invocation.namedArguments[#descending] as bool? ?? false;
        return ordered;
      });
      when(() => ordered.limit(any())).thenReturn(limited);
      when(limited.get).thenAnswer((_) async => snapshot);
      when(() => snapshot.docs).thenReturn(docs);
    }

    setUp(() => capturedDescending = null);

    test('orders createdAt DESCENDING so the cap drops the OLDEST', () async {
      // Ascending made the cap drop the newest notes, so past the cap nothing
      // anyone wrote was visible and an assignee could bury the record.
      wire([noteDoc('n1', 'one')]);

      await repo().fetchFieldNotes('a1');

      expect(capturedDescending, isTrue);
      verify(
        () => ordered.limit(AppointmentFieldNotesStore.scanLimit),
      ).called(1);
    });

    test('returns them oldest-first for display', () async {
      wire([noteDoc('newest', 'newest'), noteDoc('oldest', 'oldest')]);

      final thread = await repo().fetchFieldNotes('a1');

      expect(thread.notes.map((n) => n.id), ['oldest', 'newest']);
      expect(thread.truncated, isFalse);
    });

    test('flags truncation and warns at the cap', () async {
      final logger = _RecordingLogger();
      wire([
        for (var i = 0; i < AppointmentFieldNotesStore.scanLimit; i++)
          noteDoc('n$i', 'note $i'),
      ]);

      final thread = await FirebaseAppointmentsRepository(
        firestore,
        logger: logger,
      ).fetchFieldNotes('a1');

      expect(thread.truncated, isTrue);
      expect(
        logger.warnings.where((w) => w.startsWith('APPT-FIELDNOTE')),
        isNotEmpty,
      );
    });
  });
}
