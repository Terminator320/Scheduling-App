import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/employees/domain/models/job_title.dart';
import 'package:scheduling/features/employees/domain/policies/work_schedule_policy.dart';
import 'package:scheduling/shared/widgets/feedback/user_status_chip.dart';

/// I11: `isValidRole`, `isValidUserStatus`, `isValidJobTitle`,
/// `isValidWorkingDays`, `isMinuteOfDay`, `isValidColorValue`,
/// `isValidDocIdField` and `isValidAppointmentData` are each a hand-mirror of a
/// Dart enum or constant, and grepping any of their names across `test/`
/// returned zero — in contrast to `isValidAppointmentStatus`, which is pinned.
/// Add a sixth `JobTitle` in Dart, the chips offer it, and every save of a
/// person with that title dies as an opaque `permission-denied`.
///
/// Dart and CEL cannot share a constant, so reading the rules back as text is
/// the only mechanism available. The extraction helper is the one
/// `appointment_status_rules_test.dart` uses.
void main() {
  late final rules = File('firestore.rules').readAsStringSync();

  /// The body of the named rules function.
  String bodyOf(String name) {
    final body = RegExp(
      // The guards sit at two indentation levels (inside `match /users` and at
      // the top of the document match), so the terminator is indent-agnostic.
      'function ${RegExp.escape(name)}\\([^)]*\\)\\s*\\{(.*?)\\n\\s*\\}',
      dotAll: true,
    ).firstMatch(rules)?.group(1);
    expect(body, isNotNull, reason: '$name not found in firestore.rules');
    return body!;
  }

  /// The quoted string literals a rules function admits.
  Set<String> allowlistOf(String name) => RegExp(
    "'([a-z_]*)'",
  ).allMatches(bodyOf(name)).map((m) => m.group(1)!).toSet();

  group('user vocabulary', () {
    test('isValidRole admits exactly the two access flags', () {
      // `role` is the ACCESS flag every rules gate resolves through — a value
      // the rules admit but the app never writes is dead vocabulary that
      // invites a "restore", and one the app writes but the rules refuse fails
      // the whole employee save.
      expect(allowlistOf('isValidRole'), {'admin', 'employee'});
    });

    test('isValidUserStatus admits exactly the UserStatus enum', () {
      expect(
        allowlistOf('isValidUserStatus'),
        UserStatus.values.map((s) => s.name).toSet(),
      );
    });

    test('isValidJobTitle admits exactly the JobTitle enum', () {
      // Including the empty string: `JobTitle.unset` is a normal state (the
      // admin never picked one), not an error, and it is what `toMap` emits.
      expect(
        allowlistOf('isValidJobTitle'),
        JobTitle.values.map((t) => t.raw).toSet(),
      );
    });

    test('every pickable job title is one the rules accept', () {
      // The chips seed a real write, so an entry here the rules refuse fails
      // the save.
      final allowed = allowlistOf('isValidJobTitle');
      for (final title in JobTitle.pickable) {
        expect(
          allowed,
          contains(title.raw),
          reason: '${title.name} is offered in the chips but rejected',
        );
      }
    });

    test('isValidWorkingDays matches the stored week length', () {
      // Rules cannot iterate a list, so the SIZE is the enforceable half — and
      // `normalizeWorkingDays` is the one thing that guarantees the write has
      // it. A mismatch rejects every availability save.
      final size = RegExp(
        r'v\.size\(\)\s*==\s*(\d+)',
      ).firstMatch(bodyOf('isValidWorkingDays'))?.group(1);
      expect(size, isNotNull, reason: 'isValidWorkingDays lost its size check');
      expect(int.parse(size!), kDefaultWorkingDays.length);
      expect(normalizeWorkingDays(const []), hasLength(int.parse(size)));
      expect(
        normalizeWorkingDays(const [true, false]),
        hasLength(int.parse(size)),
      );
    });

    test('isMinuteOfDay admits every minute the picker can produce', () {
      final bounds = RegExp(
        r'v\s*>=\s*(\d+)\s*&&\s*v\s*<=\s*(\d+)',
      ).firstMatch(bodyOf('isMinuteOfDay'));
      expect(bounds, isNotNull, reason: 'isMinuteOfDay lost its bounds');
      final min = int.parse(bounds!.group(1)!);
      final max = int.parse(bounds.group(2)!);

      // `timeOfDayToMinutes` tops out at 23:59; the defaults must fit too, or a
      // brand-new employee cannot be saved at all.
      expect(timeOfDayToMinutes(const TimeOfDay(hour: 0, minute: 0)), min);
      expect(
        timeOfDayToMinutes(const TimeOfDay(hour: 23, minute: 59)),
        lessThanOrEqualTo(max),
      );
      expect(kDefaultWorkStartMinutes, inInclusiveRange(min, max));
      expect(kDefaultWorkEndMinutes, inInclusiveRange(min, max));
    });

    test('isValidColorValue accepts every crew colour the app stores', () {
      // The colour is stored as the light-theme ARGB int, rendered as a decimal
      // string — a regex that rejected one would silently fall the roster back
      // to the default blue on every save.
      final pattern = RegExp(
        r"s\.matches\('([^']+)'\)",
      ).firstMatch(bodyOf('isValidColorValue'))?.group(1);
      expect(pattern, isNotNull, reason: 'isValidColorValue lost its pattern');
      final matcher = RegExp(pattern!);

      for (final color in AppColors.crewPalette) {
        expect(
          matcher.hasMatch(color.toARGB32().toString()),
          isTrue,
          reason: '${color.toARGB32()} is written but rejected by the rules',
        );
      }
      expect(matcher.hasMatch(''), isFalse);
      expect(matcher.hasMatch('0xFF2196F3'), isFalse);
    });

    test('maxJobsPerDay: every picker option is inside the rules bound', () {
      final bound = RegExp(
        r'd\.maxJobsPerDay\s*<=\s*(\d+)',
      ).firstMatch(rules)?.group(1);
      expect(bound, isNotNull, reason: 'the maxJobsPerDay bound was removed');
      for (final option in kMaxJobsOptions) {
        expect(option, lessThanOrEqualTo(int.parse(bound!)));
        expect(option, greaterThanOrEqualTo(0));
      }
    });
  });

  group('appointment shape guards', () {
    test('isValidDocIdField keeps both halves', () {
      // The no-slash check is the load-bearing one: a doc id containing "/"
      // makes `.doc(id)` throw SYNCHRONOUSLY in the Admin SDK, and several
      // triggers build refs from these values — one poisoned appointment breaks
      // those paths for good, outliving the session that wrote it.
      final body = bodyOf('isValidDocIdField').replaceAll(RegExp(r'\s+'), ' ');
      expect(body, contains('v is string'));
      expect(body, contains("!v.matches('.*/.*')"));
      expect(
        RegExp(r'v\.size\(\)\s*<=\s*(\d+)').firstMatch(body),
        isNotNull,
        reason: 'isValidDocIdField lost its length cap',
      );
    });

    test('isValidAppointmentData guards every field toMap() emits', () {
      // `AppointmentRecord.toMap()` is what an ordinary save writes, and a
      // partial update presents every untouched field in
      // `request.resource.data` — so a field with no clause is an uncapped
      // string on a document with a hard 1 MB ceiling, and a field the guard
      // names but `toMap` no longer emits is dead vocabulary. Only the
      // instants, the bools and `status` are handled elsewhere
      // (hasValidAppointmentInstants / isValidAppointmentStatus).
      final guarded =
          RegExp(
                r"'(\w+)' in d\.keys\(\)",
              )
              .allMatches(bodyOf('isValidAppointmentData'))
              .map((m) => m.group(1)!)
              .toSet();

      // The bools are exempt because the risk this test exists for is an
      // UNCAPPED STRING riding an ordinary update up against the 1 MB document
      // ceiling — `isDayOff` joins `isPersonal`/`isAllDay` on exactly that
      // reasoning, not because anything type-checks it. (Nothing does: adding
      // `d.isDayOff is bool` would be a real, small hardening, but it belongs
      // with a clause for all three and a rules deploy.)
      const handledElsewhere = {
        'startTime',
        'endTime',
        'status',
        'isPersonal',
        'isAllDay',
        'isDayOff',
      };
      final emitted = AppointmentRecord(
        id: 'a',
        startTime: DateTime(2026, 8, 15),
        endTime: DateTime(2026, 8, 15, 1),
      ).toMap().keys.toSet();

      expect(
        emitted.difference(handledElsewhere).difference(guarded),
        isEmpty,
        reason: 'toMap() emits a field isValidAppointmentData does not cap',
      );
      // `seriesOpId` is write metadata the repository stamps rather than a
      // `toMap()` field, so the converse is scoped to what toMap DOES emit.
      expect(guarded, contains('seriesOpId'));
    });

    test('the picture-array bound is stated, and matches the read bound', () {
      // Photos are appended by `arrayUnion` from the offline upload queue, so
      // nothing client-side bounds the array — this cap is the only ceiling,
      // and `fetchAppointmentPictures` deliberately reuses its number rather
      // than inventing a second.
      final cap = RegExp(
        r'd\.pictures\.size\(\)\s*<=\s*(\d+)',
      ).firstMatch(rules)?.group(1);
      expect(cap, isNotNull, reason: 'the pictures array bound was removed');
      expect(int.parse(cap!), 100);
    });
  });
}
