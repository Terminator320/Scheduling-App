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

    test('an ASSIGNEE may add a photo row, and only add one', () {
      // Widened 2026-09-01. The read half was always theirs; the write half
      // was admin-only, so the person standing in the basement could not use
      // the photo pipeline that already existed. Adding is additive and
      // path-scoped; editing or deleting somebody else's row is a different
      // decision and stays with the admin, so a field record cannot be
      // quietly removed by the person whose work it documents.
      final block = imagesBlock();
      expect(
        block,
        contains(
          'allow create: if (isAdmin() || '
          'isAssignedEmployee(parentAppointment()))',
        ),
      );
      expect(block, contains('allow update: if isAdmin()'));
      expect(block, contains('allow delete: if isAdmin()'));
    });

    test('storage.rules grants the same assignee the BYTES', () {
      // Two stores, one grant. A row create with no matching object write
      // leaves a photo row pointing at nothing.
      final storage = File('storage.rules').readAsStringSync();
      final block = storage.substring(
        storage.indexOf('match /appointments/{appointmentId}/images/'),
      );
      expect(
        block,
        contains(
          'allow write: if (isAdmin() || '
          'isAssignedToAppointment(appointmentId))',
        ),
      );
      // And only the bytes: delete stays admin-only on BOTH sides.
      expect(block, contains('allow delete: if isAdmin();'));
    });

    test('storagePath is scoped to THIS appointment, not merely capped', () {
      // The 500-char cap alone let a compromised admin session plant a row
      // pointing at another appointment's object, making that photo readable
      // by the SECOND appointment's assignees through the read rule above.
      // ImageStorageService.upload builds exactly this shape, and
      // storage.rules gates the bytes at the same path.
      final block = imagesBlock();
      expect(block, contains('request.resource.data.storagePath.matches('));
      expect(
        block,
        contains("'appointments/' + appointmentId + '/images/.*'"),
      );
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

    test('create accepts it only as an explicit zero', () {
      // The one client write allowed, and the reason "absent" is not a third
      // state the app has to interpret: the trigger only fires on a photo
      // write, so a job created without it would read as count-unknown until
      // its first photo — and the detail sheet gates its subcollection read on
      // this number. Pinning the value keeps a client from claiming a count it
      // has not earned.
      expect(
        rules,
        contains("!('pictureCount' in request.resource.data.keys())"),
      );
      expect(rules, contains('request.resource.data.pictureCount == 0'));
    });

    test('update is DIFF-based, not a flat ban', () {
      // The trigger's own value is present in request.resource.data on every
      // partial update, so a flat ban would reject every ordinary edit of a
      // job that has photos — the same asymmetry as emergencyFieldNotSet.
      final update = rules.substring(rules.indexOf('allow update: if (isAdmin()'));
      expect(update, contains("affectedKeys().hasAny(['pictureCount'])"));
    });
  });

  group('the retired pictures array', () {
    test('the cap survives for documents the cleanup script has not reached',
        () {
      // Nothing writes the array now, but a legacy document still carries one
      // and it rides along in request.resource.data on every ordinary edit.
      // Dropping the clause would let an Admin-SDK or console write grow one
      // past the parent's 1 MB ceiling and make the job permanently
      // un-updatable.
      expect(rules, contains("!('pictures' in d.keys())"));
      expect(rules, contains('d.pictures.size() <= 100'));
    });

    test('it is a cap, never a ban', () {
      // A flat ban would refuse every edit of a document still holding an
      // array — the same trap `pictureCount`'s update branch avoids.
      expect(
        rules,
        isNot(contains("!('pictures' in request.resource.data.keys())")),
      );
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
    // Nor the array it replaced: a write that recreated it would grow the
    // parent document again, which is the whole thing this move undid.
    expect(body, isNot(contains('pictures')));
  });
}
