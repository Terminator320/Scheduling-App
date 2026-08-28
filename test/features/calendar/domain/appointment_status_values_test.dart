// Pins the ONE terminal-status vocabulary against its enum mirror.
//
// "Terminal appointment status" used to have four independent definitions and
// one had drifted: the History query listed only done/cancelled, so a legacy
// `completed` doc rendered as Done on its card and was invisible in History
// and history search, with no error anywhere. These tests fail if any of the
// remaining owners disagree again.

import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/calendar/domain/appointment_status_values.dart';

void main() {
  group('terminalStatusRawValues', () {
    test('carries the legacy `completed` alias', () {
      // The one value the History query had dropped.
      expect(terminalStatusRawValues, contains('completed'));
      expect(isTerminalStatusRaw('completed'), isTrue);
    });

    test('matches case-insensitively', () {
      expect(isTerminalStatusRaw('DONE'), isTrue);
      expect(isTerminalStatusRaw('Cancelled'), isTrue);
    });

    test('open statuses are not terminal', () {
      expect(isTerminalStatusRaw('pending'), isFalse);
      expect(isTerminalStatusRaw('in_progress'), isFalse);
      expect(isTerminalStatusRaw(''), isFalse);
    });
  });

  group('the AppointmentStatus mirror', () {
    test('every raw terminal value maps to a terminal enum value', () {
      for (final raw in terminalStatusRawValues) {
        expect(
          AppointmentStatus.fromRaw(raw).isTerminal,
          isTrue,
          reason: '"$raw" is terminal for the query but not for the enum',
        );
      }
    });

    test('no pickable status is terminal by the raw vocabulary', () {
      // pending and in_progress round-trip through storedRaw, so if either
      // leaked into the set the History query would swallow live work.
      for (final status in AppointmentStatus.appointmentValues) {
        expect(
          isTerminalStatusRaw(status.raw),
          status.isTerminal,
          reason: '${status.name} disagrees across the two owners',
        );
      }
    });
  });

  group('terminalStatusQueryValues', () {
    test('is the same vocabulary, not a second spelling', () {
      expect(terminalStatusQueryValues.toSet(), terminalStatusRawValues);
    });

    test('fits a Firestore whereIn constraint', () {
      expect(terminalStatusQueryValues.length, lessThanOrEqualTo(30));
    });
  });
}
