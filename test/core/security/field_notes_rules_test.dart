import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Rules cannot be unit-tested without the emulator, so — like
/// `appointment_images_rules_test.dart` — this reads `firestore.rules` back as
/// TEXT and pins the properties the crew-notes grant stands on.
void main() {
  late final rules = File('firestore.rules').readAsStringSync();

  String notesBlock() {
    final start = rules.indexOf('match /fieldNotes/{noteId}');
    expect(
      start,
      greaterThan(-1),
      reason:
          'the crew-notes subcollection has no rules block, so every note '
          'read and write is denied by default',
    );
    final end = rules.indexOf('\n      }', start);
    return rules.substring(start, end == -1 ? rules.length : end);
  }

  String collapsed(String source) =>
      source.replaceAll(RegExp('//[^\n]*'), '').replaceAll(RegExp(r'\s+'), ' ');

  test('read is admin OR an assignee of THIS appointment', () {
    final block = notesBlock();
    expect(block, contains('allow read:'));
    expect(block, contains('isAdmin()'));
    expect(block, contains('isAssignedEmployee(parentAppointment())'));
  });

  test('an assignee may ADD a note', () {
    expect(
      collapsed(notesBlock()),
      contains(
        'allow create: if (isAdmin() || '
        'isAssignedEmployee(parentAppointment()))',
      ),
    );
  });

  test('a note can only be filed under the CALLER own doc id', () {
    // Without this an assignee could post a note signed with a colleague name.
    expect(
      collapsed(notesBlock()),
      contains('request.resource.data.authorId == myDocId()'),
    );
  });

  test('the key set is exact', () {
    expect(
      collapsed(notesBlock()),
      contains(
        "hasOnly( ['text', 'authorId', 'authorName', 'createdAt'])".replaceAll(
          RegExp(r'\s+'),
          ' ',
        ),
      ),
    );
  });

  test('text and authorName are length-capped and createdAt is pinned', () {
    final block = collapsed(notesBlock());
    expect(
      block,
      contains('isBoundedString(request.resource.data.text, 4000)'),
    );
    expect(
      block,
      contains('isBoundedString(request.resource.data.authorName, 200)'),
    );
    expect(block, contains('request.resource.data.createdAt == request.time'));
  });

  test('editing and deleting a note stay ADMIN-ONLY', () {
    // A field record must not be quietly rewritten by the person whose work it
    // documents - the same posture the images subcollection takes.
    final block = notesBlock();
    expect(block, contains('allow update: if isAdmin()'));
    expect(block, contains('allow delete: if isAdmin()'));
  });

  test('the parent assignee update disjuncts are UNCHANGED', () {
    // A note write must not touch the parent document, so this adds no
    // disjunct - appointment_employee_update_rules_test.dart pins the count at
    // three and this test says why that number did not move.
    expect('|| (isAssignedEmployee(resource.data)'.allMatches(rules).length, 3);
  });
}
