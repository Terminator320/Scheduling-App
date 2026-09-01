import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// S2: the employee branch of `allow update` on `/appointments` is the only
/// write an assignee can make, and it is the ONLY gate on that write —
/// `DetailsActionBar` hides the button (`!isDone && !isCancelled`) but a
/// modified client never runs it. The branch used to test
/// what was being WRITTEN and never what was STORED, so `done` could go over
/// `cancelled` and resurrect a cancelled visit as a completed one in History,
/// in the dashboard tallies and in `purgeExpiredHistory`'s accounting.
///
/// The other half of the branch is a deliberate ABSENCE: there is no date
/// restriction, because an employee who misses the button before midnight, or
/// who is on day 2+ of a multi-day run, has no other way to close the job (the
/// edit form's status picker is admin-only) while the server keeps sending
/// "job finished?" nudges. Both halves are pinned here — the guard so it is not
/// dropped, the absence so it is not "tightened".
///
/// Rules cannot be unit-tested without the emulator, so reading them back as
/// text is the only mechanism available — the same one
/// `appointment_status_rules_test.dart`, `appointment_span_rules_test.dart`
/// and `emergency_contact_rules_test.dart` use.
void main() {
  late final rules = File('firestore.rules').readAsStringSync();

  /// Every assigned-employee disjunct of `allow update`, body only.
  ///
  /// There are TWO since 2026-09-01 — the mark-done flip and the crew notes
  /// write — so a helper that cut at the first `);` after the first
  /// `isAssignedEmployee(` would now return BOTH, and a term-ABSENCE
  /// assertion over the pair would pass for the wrong reason.
  ///
  /// Split on literals rather than a regex. The split consumes each branch's
  /// own opening marker, so a part already stops before the NEXT branch; the
  /// last one is cut at the `);` that closes the whole `allow update`.
  /// Comments riding along are harmless — every assertion here runs through
  /// [collapsed], which drops them.
  List<String> employeeBranches() {
    final parts = rules.split('|| (isAssignedEmployee(resource.data)');
    expect(
      parts.length,
      greaterThan(1),
      reason: 'the assigned-employee branches of allow update were removed',
    );
    return [
      for (final part in parts.skip(1))
        part.contains(');')
            ? part.substring(0, part.indexOf(');') + 1)
            : part,
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
  String employeeBranch() => employeeBranchNaming("'status'");

  /// The branch as the rules ENGINE sees it: comments dropped, whitespace
  /// flattened. Dropping comments is what stops a term-absence assertion below
  /// from firing on prose that merely mentions the term it forbids.
  String collapsed(String source) =>
      source.replaceAll(RegExp('//[^\n]*'), '').replaceAll(RegExp(r'\s+'), ' ');

  test('the branch still restricts the diff to status and updatedAt', () {
    // The guard below is only safe because this is exact about what MAY
    // change: without it an assignee could carry any other field along.
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
    // Deliberately `!= 'cancelled'` rather than
    // `resource.data.status in ['pending', 'in_progress']`: legacy docs carry
    // `confirmed` and other off-allowlist values (see
    // `AppointmentStatus.storedRaw`), the action bar offers the close button on
    // them, and an allowlist would refuse that close as an opaque
    // `permission-denied`. It also keeps a re-tap on an already-`done` job
    // harmless.
    final branch = collapsed(employeeBranch());
    expect(branch, isNot(contains('resource.data.status in [')));
    expect(branch, isNot(contains("resource.data.status == 'pending'")));
  });

  test('updatedAt is pinned to the server clock', () {
    // S1: the diff restriction admits `updatedAt`, so without this an assignee
    // running a modified client could stamp an arbitrary — future, past, or
    // non-timestamp — value on any job they are assigned to. Nothing
    // server-side branches on an appointment's `updatedAt`, so this is
    // audit-trail integrity rather than an exploitable defect; it is the same
    // pin the presence rule puts on its own `updatedAt`, and it is safe
    // because BOTH client write paths send `FieldValue.serverTimestamp()`
    // unconditionally.
    expect(
      collapsed(employeeBranch()),
      contains('request.resource.data.updatedAt == request.time'),
    );
  });

  test('the branch carries NO date restriction, deliberately', () {
    // The documented invariant: "Mark as complete" carries no clock gate at
    // all, and the rules allow an assignee to write `status:'done'` with no
    // date restriction. A `request.time` / instant comparison creeping in here
    // silently strands an employee on day 2+ of a multi-day run, or one who
    // taps the button after midnight, with a job they cannot close.
    //
    // The `updatedAt` pin above is the ONE exempt mention of the clock, and it
    // is exempt because it is not a restriction at all: it constrains the
    // value being WRITTEN, names no date on the appointment, and can refuse a
    // close at no hour. Anything else reading the clock here would.
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
    // complete" and nothing else — no way to record what they found, on a
    // trade where the field record IS the billable artifact and the upsell
    // pipeline. It travelled by phone call instead.
    String notesBranch() => employeeBranchNaming("'fieldNotes'");

    test('is a SEPARATE disjunct from the mark-done flip', () {
      // Not a widened `hasOnly` on the status branch: that branch is the most
      // security-sensitive write in the app and its exact key set is what
      // makes it possible to reason about. One write doing both would put
      // every guarantee above it back in play.
      expect(employeeBranches(), hasLength(2));
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
      // booked, and an assignee must not be able to overwrite it. Keeping
      // them separate is what makes "the crew may add, never edit the brief"
      // a rules-level fact rather than a UI convention.
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

    test('the cap is conditional, so an updatedAt-only touch still passes',
        () {
      // `hasOnly` admits a SUBSET, and an assignee adding a photo touches this
      // document with an `updatedAt`-only diff — the images store bumps the
      // parent in the same batch as the rows. A flat cap evaluates against an
      // ABSENT field on that write and refuses the whole batch, so the crew
      // could add a photo row and never the photo.
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
      // Unlike mark-done. A note is additive and is often the explanation for
      // a job that went wrong — "nobody home", "needs a part" — so a
      // cancelled or already-closed visit is exactly when one is worth
      // recording.
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
      // The admin re-serializes the whole record, so the cap has to live in
      // the shape guard too or a long note is only bounded on one of the two
      // ways it can be written.
      expect(
        rules,
        contains("!('fieldNotes' in d.keys()) || "
            'isBoundedString(d.fieldNotes, 4000)'),
      );
    });
  });
}
