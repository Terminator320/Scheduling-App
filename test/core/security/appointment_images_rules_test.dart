import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Rules cannot be unit-tested without the emulator, so — like
/// `appointment_span_rules_test.dart`, `emergency_contact_rules_test.dart` and
/// `self_service_rules_test.dart` — this reads `firestore.rules` back as TEXT
/// and pins the properties that are load-bearing for the photo-subcollection
/// migration. It proves the rule SAYS the right thing, not that Firestore
/// evaluates it that way; a behavioural harness is separate work.
void main() {
  late final rules = File('firestore.rules').readAsStringSync();

  /// The body of the `match /images/{imageId}` block.
  String imagesBlock() {
    final start = rules.indexOf('match /images/{imageId}');
    expect(
      start,
      greaterThan(-1),
      reason: 'the appointments images subcollection has no rules block, so '
          'every photo read and write is denied by default',
    );
    // Runs to the end of the enclosing appointments match block.
    final end = rules.indexOf('\n    }', start);
    return rules.substring(start, end == -1 ? rules.length : end);
  }

  group('the images subcollection is gated like its parent', () {
    test('read is admin OR an assignee of THIS appointment', () {
      final block = imagesBlock();
      expect(block, contains('allow read:'));
      expect(block, contains('isAdmin()'));
      // Resolved from the PARENT document rather than restating the condition.
      // Restating is how the two drift, and a drift here means a photo
      // readable by someone the job is not.
      expect(block, contains('isAssignedEmployee(parentAppointment())'));
    });

    test('parentAppointment() resolves the appointment being scoped to', () {
      // The wildcard has to be the enclosing match's `appointmentId`. Bound to
      // anything else, the rule authorises against a different job's crew.
      expect(
        imagesBlock(),
        contains(
          r'get(/databases/$(database)/documents/appointments/$(appointmentId))',
        ),
      );
    });

    test('writes are admin-only, so an employee cannot fabricate a photo row',
        () {
      final block = imagesBlock();
      expect(block, contains('allow create, update: if isAdmin()'));
      expect(block, contains('allow delete: if isAdmin()'));
    });

    test('the document shape is locked', () {
      // hasOnly, so an unnamed key rejects the whole write — the same posture
      // as every other self-writable subcollection in this file.
      final block = imagesBlock();
      expect(block, contains('hasOnly('));
      expect(block, contains('storagePath'));
      expect(block, contains('uploadedAt'));
    });
  });

  group('pictureCount is function-owned', () {
    // recountAppointmentPictures writes it as an absolute count() aggregate
    // over the subcollection, and AppointmentCard's photo indicator reads it.
    // A client write could only ever put it out of step with the photos it
    // claims to count.

    test('create bans the key outright', () {
      // A create has no existing doc to strand, so the flat ban is safe there.
      expect(
        rules,
        contains("!('pictureCount' in request.resource.data.keys())"),
      );
    });

    test('update is DIFF-based, not a flat ban', () {
      // The trigger's own value is present in request.resource.data on every
      // partial update, so a flat ban would reject every ordinary edit of a
      // job that has photos — the same asymmetry as emergencyFieldNotSet.
      final update = rules.substring(rules.indexOf('allow update: if (isAdmin()'));
      expect(update, contains("affectedKeys().hasAny(['pictureCount'])"));
    });
  });

  test('AppointmentRecord.toMap does not emit pictureCount', () {
    // The rules above reject a write that touches it, so emitting it from
    // toMap would turn every appointment save into an opaque
    // permission-denied. Same contract as jobCount/wave on a client.
    final model = File(
      'lib/features/calendar/domain/models/appointment_record.dart',
    ).readAsStringSync();
    final toMap = model.substring(model.indexOf('Map<String, dynamic> toMap()'));
    final body = toMap.substring(0, toMap.indexOf('};'));
    expect(body, isNot(contains('pictureCount')));
  });
}
