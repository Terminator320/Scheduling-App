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

  /// The body of the assigned-employee disjunct of `allow update`.
  String employeeBranch() {
    final body = RegExp(
      r'\|\| \(isAssignedEmployee\(resource\.data\)(.*?)\);',
      dotAll: true,
    ).firstMatch(rules)?.group(1);
    expect(
      body,
      isNotNull,
      reason: 'the assigned-employee branch of allow update was removed',
    );
    return body!;
  }

  String collapsed(String source) => source.replaceAll(RegExp(r'\s+'), ' ');

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

  test('the branch carries NO date restriction, deliberately', () {
    // The documented invariant: "Mark as complete" carries no clock gate at
    // all, and the rules allow an assignee to write `status:'done'` with no
    // date restriction. A `request.time` / instant comparison creeping in here
    // silently strands an employee on day 2+ of a multi-day run, or one who
    // taps the button after midnight, with a job they cannot close.
    final branch = employeeBranch();
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
}
