import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// S2: the employee branch of `allow update` on `/appointments` is the only
/// write an assignee can make, and it is the ONLY gate on that write —
/// `DetailsActionBar` hides the button (`!isDone && !isCancelled`) but a
/// modified client never runs it.
void main() {
  late final rules = File('firestore.rules').readAsStringSync();

  /// Every assigned-employee disjunct of `allow update`, body only.
  List<String> employeeBranches() {
    final parts = rules.split('|| (isAssignedEmployee(resource.data)');
    expect(
      parts.length,
      greaterThan(1),
      reason: 'the assigned-employee branches of allow update were removed',
    );
    return [
      for (final part in parts.skip(1))
        if (part.contains(');'))
          part.substring(0, part.indexOf(');') + 1)
        else
          part,
    ];
  }

  /// The disjunct whose `hasOnly` names [firstKey].
  String employeeBranchNaming(String firstKey) {
    for (final branch in employeeBranches()) {
      if (branch.contains(firstKey)) return branch;
    }
    fail('no assigned-employee branch of allow update names $firstKey');
  }

  /// The mark-done branch — what every pre-existing test here means by "the"
  /// employee branch.
  String employeeBranch() => employeeBranchNaming("== 'done'");

  /// The branch as the rules ENGINE sees it: comments dropped, whitespace
  /// flattened.
  String collapsed(String source) =>
      source.replaceAll(RegExp('//[^\n]*'), '').replaceAll(RegExp(r'\s+'), ' ');

  test('the branch still restricts the diff to status and updatedAt', () {
    // The guard below is only safe because this is exact about what MAY change:
    // without it an assignee could carry any other field along.
    expect(
      collapsed(employeeBranch()),
      contains("affectedKeys() .hasOnly(['status', 'updatedAt'])"),
    );
  });

  test('the branch still only ever writes done', () {
    expect(
      collapsed(employeeBranch()),
      contains("request.resource.data.status == 'done'"),
    );
  });

  test('a cancelled job can no longer be flipped to done', () {
    // The finding. Without this term the branch inspects the incoming status
    // alone, so `done` over `cancelled` passes and re-fires
    // notifyAppointmentChanges / endCardOnTerminal on a job the admin closed.
    expect(
      collapsed(employeeBranch()),
      contains("resource.data.status != 'cancelled'"),
    );
  });

  test('the stored-status guard is a refusal of cancelled, not an allowlist', () {
    // Deliberately `!= 'cancelled'` rather than `resource.data.status in
    // ['pending', 'in_progress']`: legacy docs carry `confirmed` and other
    // off-allowlist values (see `AppointmentStatus.storedRaw`), the action bar
    // offers the close button on them, and an allowlist would refuse that close
    // as an opaque `permission-denied`.
    final branch = collapsed(employeeBranch());
    expect(branch, isNot(contains('resource.data.status in [')));
    expect(branch, isNot(contains("resource.data.status == 'pending'")));
  });

  test('updatedAt is pinned to the server clock', () {
    // S1: the diff restriction admits `updatedAt`, so without this an assignee
    // running a modified client could stamp an arbitrary — future, past, or
    // non-timestamp — value on any job they are assigned to.
    expect(
      collapsed(employeeBranch()),
      contains('request.resource.data.updatedAt == request.time'),
    );
  });

  test('the branch carries NO date restriction, deliberately', () {
    // The documented invariant: "Mark as complete" carries no clock gate at
    // all, and the rules allow an assignee to write `status:'done'` with no
    // date restriction.
    final branch = collapsed(
      employeeBranch(),
    ).replaceAll('request.resource.data.updatedAt == request.time', '');
    for (final term in const [
      'request.time',
      'duration.value',
      'startTime',
      'endTime',
      'timestamp',
    ]) {
      expect(
        branch,
        isNot(contains(term)),
        reason: '"$term" reads as a date restriction on the employee branch',
      );
    }
  });

  test('the shape guards stay on the ADMIN branch only', () {
    // An assignee's status flip must keep working on a legacy doc that predates
    // the caps and the span bound — the diff restriction above is what makes
    // skipping them safe.
    final branch = employeeBranch();
    expect(branch, isNot(contains('isValidAppointmentData')));
    expect(branch, isNot(contains('isValidAppointmentSpan')));
    expect(branch, isNot(contains('appointmentSpanNotWidened')));
  });

  group('the crew-notes branch', () {
    // Added 2026-09-01. The technician could read a job and tap "Mark as
    // complete" and nothing else — no way to record what they found, on a trade
    // where the field record IS the billable artifact and the upsell pipeline.
    // It travelled by phone call instead.
    String notesBranch() => employeeBranchNaming("'fieldNotes'");

    test('is a SEPARATE disjunct from the mark-done flip', () {
      // Not a widened `hasOnly` on the status branch: that branch is the most
      // security-sensitive write in the app and its exact key set is what makes
      // it possible to reason about.
      expect(employeeBranches(), hasLength(3));
      expect(collapsed(employeeBranch()), isNot(contains("'fieldNotes'")));
      expect(collapsed(notesBranch()), isNot(contains("'status'")));
    });

    test('restricts the diff to fieldNotes and updatedAt', () {
      expect(
        collapsed(notesBranch()),
        contains("affectedKeys() .hasOnly(['fieldNotes', 'updatedAt'])"),
      );
    });

    test('writes fieldNotes, never the dispatcher NOTES field', () {
      // Two fields on purpose: `notes` is the brief written when the job was
      // booked, and an assignee must not be able to overwrite it.
      final body = collapsed(notesBranch());
      expect(body, contains("'fieldNotes'"));
      expect(body, isNot(contains("['notes'")));
      expect(body, isNot(contains("'notes',")));
    });

    test('bounds the string', () {
      expect(
        collapsed(notesBranch()),
        contains('isBoundedString(request.resource.data.fieldNotes, 4000)'),
      );
    });

    test('the cap is conditional, so an updatedAt-only touch still passes', () {
      // `hasOnly` admits a SUBSET, and an assignee adding a photo touches this
      // document with an `updatedAt`-only diff — the images store bumps the
      // parent in the same batch as the rows.
      expect(
        collapsed(notesBranch()),
        contains("!('fieldNotes' in request.resource.data)"),
      );
    });

    test('pins updatedAt, like the flip beside it', () {
      expect(
        collapsed(notesBranch()),
        contains('request.resource.data.updatedAt == request.time'),
      );
    });

    test('carries NO status gate, deliberately', () {
      // Unlike mark-done. A note is additive and is often the explanation for a
      // job that went wrong — "nobody home", "needs a part" — so a cancelled or
      // already-closed visit is exactly when one is worth recording.
      final body = collapsed(notesBranch());
      expect(body, isNot(contains("status != 'cancelled'")));
      expect(body, isNot(contains('status ==')));
    });

    test('the shape guards stay off this branch too', () {
      // Same reasoning as the flip: a legacy doc predating the caps must stay
      // note-able, and the diff is already restricted to two keys.
      final body = collapsed(notesBranch());
      expect(body, isNot(contains('isValidAppointmentData')));
      expect(body, isNot(contains('isValidAppointmentSpan')));
    });

    test('the field is capped on the ADMIN path as well', () {
      // The admin re-serializes the whole record, so the cap has to live in the
      // shape guard too or a long note is only bounded on one of the two ways
      // it can be written.
      expect(
        rules,
        contains(
          "!('fieldNotes' in d.keys()) || "
          'isBoundedString(d.fieldNotes, 4000)',
        ),
      );
    });
  });
}
