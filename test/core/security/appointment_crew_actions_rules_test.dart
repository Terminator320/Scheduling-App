import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The two assigned-employee branches added 2026-09-01 — "Start job" and the
/// "On my way" / "Running late" signal — and the one thing they must NOT have
/// done: widen the mark-done branch.
void main() {
  late final rules = File('firestore.rules').readAsStringSync();

  List<String> employeeBranches() {
    final parts = rules.split('|| (isAssignedEmployee(resource.data)');
    expect(parts.length, greaterThan(1));
    return [
      for (final part in parts.skip(1))
        part.contains(');') ? part.substring(0, part.indexOf(');') + 1) : part,
    ];
  }

  String collapsed(String source) =>
      source.replaceAll(RegExp('//[^\n]*'), '').replaceAll(RegExp(r'\s+'), ' ');

  String branchNaming(String term) {
    for (final branch in employeeBranches()) {
      if (collapsed(branch).contains(term)) return collapsed(branch);
    }
    fail('no assigned-employee branch names $term');
  }

  String markDone() => branchNaming("== 'done'");
  String startJob() => branchNaming("== 'in_progress'");
  String crewStatus() => branchNaming("'crewStatus'");

  group('the mark-done branch is untouched', () {
    test('still restricts the diff to status and updatedAt', () {
      expect(
        markDone(),
        contains("affectedKeys() .hasOnly(['status', 'updatedAt'])"),
      );
    });

    test('no employee branch writes the time record', () {
      // `startedAt`/`completedAt` are stamped SERVER-SIDE by the write trigger.
      for (final branch in employeeBranches()) {
        final body = collapsed(branch);
        expect(body, isNot(contains("'startedAt'")));
        expect(body, isNot(contains("'completedAt'")));
      }
    });
  });

  group('the Start-job branch', () {
    test('is its own disjunct with the same two-key diff', () {
      expect(
        startJob(),
        contains("affectedKeys() .hasOnly(['status', 'updatedAt'])"),
      );
      expect(startJob(), isNot(contains("== 'done'")));
    });

    test('only ever writes in_progress', () {
      expect(
        startJob(),
        contains("request.resource.data.status == 'in_progress'"),
      );
    });

    test(
      'moves a job FORWARD only: never from in-progress or a closed state',
      () {
        final body = startJob();
        for (final closed in const [
          'in_progress',
          'done',
          'completed',
          'cancelled',
        ]) {
          expect(body, contains("'$closed'"));
        }
        expect(body, contains('!(resource.data.status in'));
      },
    );

    test('pins updatedAt to the server clock', () {
      expect(
        startJob(),
        contains('request.resource.data.updatedAt == request.time'),
      );
    });
  });

  group('the crew-status branch', () {
    test('restricts the diff to exactly the four crew-status keys', () {
      expect(
        crewStatus(),
        contains(
          "affectedKeys() .hasOnly(['crewStatus', 'crewStatusAt', "
          "'crewStatusBy', 'updatedAt'])",
        ),
      );
      expect(crewStatus(), isNot(contains("'status'")));
    });

    test('admits only the two signal strings', () {
      expect(
        crewStatus(),
        contains(
          "request.resource.data.crewStatus in ['onMyWay', 'runningLate']",
        ),
      );
    });

    test('pins both instants to the server clock', () {
      expect(
        crewStatus(),
        contains('request.resource.data.crewStatusAt == request.time'),
      );
      expect(
        crewStatus(),
        contains('request.resource.data.updatedAt == request.time'),
      );
    });

    test("a signal can only be sent in the caller's own name", () {
      expect(
        crewStatus(),
        contains('request.resource.data.crewStatusBy == myDocId()'),
      );
    });

    test('is refused on a closed job', () {
      expect(
        crewStatus(),
        contains(
          "!(resource.data.status in ['done', 'completed', 'cancelled'])",
        ),
      );
    });
  });

  group('the admin shape guard', () {
    // `request.resource.data` on an admin edit is the MERGED document, so the
    // server-stamped instants ride along: they must be type-checked, never
    // banned, or every edit of a started job is refused.
    late final validator = collapsed(
      rules.substring(
        rules.indexOf('function isValidAppointmentData(d)'),
        rules.indexOf('match /appointments/{appointmentId}'),
      ),
    );

    test('caps the crew signal and its sender', () {
      expect(validator, contains('isBoundedString(d.crewStatus, 32)'));
      expect(validator, contains('isValidDocIdField(d.crewStatusBy)'));
    });

    test('type-checks the three instants, absent-or-valid', () {
      for (final field in const ['startedAt', 'completedAt', 'crewStatusAt']) {
        expect(
          validator,
          contains("(!('$field' in d.keys()) || d.$field is timestamp)"),
        );
      }
    });
  });
}
