import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/calendar/domain/models/field_note.dart';

void main() {
  test('fromMap reads every stored field', () {
    final note = FieldNote.fromMap('n1', {
      'text': 'Copper feed corroded at the elbow.',
      'authorId': 'e1',
      'authorName': 'Marc Tremblay',
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 9, 6, 8, 42)),
    });
    expect(note.id, 'n1');
    expect(note.text, 'Copper feed corroded at the elbow.');
    expect(note.authorId, 'e1');
    expect(note.authorName, 'Marc Tremblay');
    // Timestamp.toDate() is never UTC-flagged, so compare the instant, not the object.
    expect(note.createdAt?.toUtc(), DateTime.utc(2026, 9, 6, 8, 42));
  });

  test('a missing author degrades to empty rather than throwing', () {
    // A console-written or partially-migrated row must still render.
    final note = FieldNote.fromMap('n2', const {'text': 'hi'});
    expect(note.authorId, '');
    expect(note.authorName, '');
    expect(note.createdAt, isNull);
  });

  test('the legacy single string becomes an unattributed note', () {
    final note = FieldNote.legacy('Shutoff valve is behind the dryer.');
    expect(note.id, FieldNote.legacyId);
    expect(note.text, 'Shutoff valve is behind the dryer.');
    expect(note.authorId, isEmpty);
    expect(note.authorName, isEmpty);
  });
}
