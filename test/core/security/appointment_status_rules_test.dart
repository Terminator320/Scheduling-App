import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/calendar/domain/appointment_status_values.dart';

/// I6: the appointment status allowlist is one of the most load-bearing
/// duplications in the codebase — `isValidAppointmentStatus` in
/// `firestore.rules`, `_allowedStatuses` in
/// `firebase_appointments_repository.dart`, and `AppointmentStatus` — and it
/// was the one such mirror with nothing policing it. A value the rules reject
/// reaches the user as an opaque `permission-denied` on an ordinary save; a
/// value the rules allow but the app never writes is dead vocabulary that
/// invites a "restore". The 2026-08-14 audit found the DOCUMENTATION copy of
/// this list had already drifted back to the retired `confirmed`.
///
/// Reading the rules and the repository back as text is the only mechanism
/// available — Dart and CEL cannot share a constant — the same way
/// `text_limits_test.dart`, `self_service_fields_test.dart` and
/// `appointment_span_rules_test.dart` police theirs.
void main() {
  late final rules = File('firestore.rules').readAsStringSync();
  late final repository = File(
    'lib/features/calendar/data/firebase_appointments_repository.dart',
  ).readAsStringSync();

  /// The statuses `isValidAppointmentStatus` admits.
  Set<String> rulesAllowlist() {
    final body = RegExp(
      r'function isValidAppointmentStatus\([^)]*\)\s*\{(.*?)\n    \}',
      dotAll: true,
    ).firstMatch(rules)?.group(1);
    expect(body, isNotNull, reason: 'isValidAppointmentStatus not found');
    return RegExp(
      "'([a-z_]+)'",
    ).allMatches(body!).map((m) => m.group(1)!).toSet();
  }

  /// The statuses `_allowedStatuses` admits.
  Set<String> repositoryAllowlist() {
    final body = RegExp(
      r'_allowedStatuses = \{(.*?)\};',
      dotAll: true,
    ).firstMatch(repository)?.group(1);
    expect(body, isNotNull, reason: '_allowedStatuses not found');
    return RegExp(
      "'([a-z_]+)'",
    ).allMatches(body!).map((m) => m.group(1)!).toSet();
  }

  test('the rules and the repository allow exactly the same four', () {
    expect(rulesAllowlist(), {'pending', 'in_progress', 'done', 'cancelled'});
    expect(repositoryAllowlist(), rulesAllowlist());
  });

  test('every status the picker offers is one the rules accept', () {
    // The picker seeds a real write, so an entry here that the rules refuse
    // fails the whole save. `overdue` is display-only and deliberately absent
    // — reading its `.raw` throws on purpose.
    for (final status in AppointmentStatus.appointmentValues) {
      expect(
        rulesAllowlist(),
        contains(status.raw),
        reason: '${status.name} is offered in the picker but rejected',
      );
    }
  });

  test('storedRaw can only ever emit an allowlisted value', () {
    // Every re-serialization of a stored record goes through `storedRaw`, so
    // this is the property that keeps a legacy `confirmed` doc, an unknown
    // value and display-only `overdue` from failing the save.
    const inputs = [
      'pending',
      'in_progress',
      'done',
      'completed',
      'cancelled',
      'confirmed',
      'overdue',
      '',
      'not-a-status',
    ];
    for (final raw in inputs) {
      expect(
        rulesAllowlist(),
        contains(AppointmentStatus.storedRaw(raw)),
        reason: 'storedRaw("$raw") is off the rules allowlist',
      );
    }
  });

  test('the terminal vocabulary is a superset the rules never has to know', () {
    // `completed` is a legacy alias the app READS but never writes, so it is
    // deliberately absent from the rules. Pinned so a future "tidy" doesn't
    // add it to the allowlist (which would let it be written again) or drop
    // it from the terminal set (which made such docs invisible in History).
    expect(terminalStatusRawValues, contains('completed'));
    expect(rulesAllowlist(), isNot(contains('completed')));
    expect(rulesAllowlist(), isNot(contains('confirmed')));
  });
}
