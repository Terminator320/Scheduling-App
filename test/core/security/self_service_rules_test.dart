import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// P5's self-service clause. `isAvailabilityOnlyChange()` was written in P4 and
/// deliberately left uncalled until there was a UI behind it; this pins the
/// call, and pins the two things that make it safe to grant.
///
/// Rules cannot be unit-tested without the emulator, so this reads
/// `firestore.rules` back as text — the same mechanism
/// `emergency_contact_rules_test.dart` and `text_limits_test.dart` use.
void main() {
  late final rules = File('firestore.rules').readAsStringSync();

  group('users self-service update', () {
    test('allow update carries the self clause', () {
      final updateBlock = RegExp(
        'allow update: if(.*?);',
        dotAll: true,
      ).firstMatch(rules)?.group(1);

      expect(updateBlock, isNotNull, reason: 'allow update was restructured');
      expect(updateBlock, contains('isSelf()'));
      expect(updateBlock, contains('isAvailabilityOnlyChange()'));
    });

    test('the admin branch keeps the denylist and the validator', () {
      // The disjunction must be parenthesized. Without the brackets the
      // denylist and isValidUserData bind to the self branch alone, and an
      // admin write skips both.
      final updateBlock = RegExp(
        'allow update: if(.*?);',
        dotAll: true,
      ).firstMatch(rules)?.group(1);

      expect(updateBlock, contains('(isAdmin() || (isSelf()'));
      expect(updateBlock, contains('isValidUserData(request.resource.data)'));
      expect(updateBlock, contains('termsAcceptedAt'));
    });

    test('isSelf requires an ACTIVE account, not just a uid match', () {
      // A disabled account keeps its Auth credential until syncUsersByUid
      // revokes it, and an invited one is mid-setup. Neither may self-edit.
      final fn = RegExp(
        r'function isSelf\(\)\s*\{(.*?)\}',
        dotAll: true,
      ).firstMatch(rules)?.group(1);

      expect(fn, isNotNull, reason: 'isSelf() was removed');
      expect(fn, contains('isActiveUser()'));
      expect(fn, contains('resource.data.uid == request.auth.uid'));
    });

    test('the self branch PINS updatedAt to request.time', () {
      // `updatedAt` is on the hasOnly allowlist but absent from
      // isValidUserData, which has no hasOnly of its own — so an unlisted key
      // is unchecked, and this was the last client-writable field on the doc
      // with no bound at all. watchEmployees() holds a live snapshots() over
      // active docs on every signed-in device, so one inflated value is
      // re-delivered to every peer on every snapshot.
      final fn = RegExp(
        r'function isAvailabilityOnlyChange\(\)\s*\{(.*?)\n      \}',
        dotAll: true,
      ).firstMatch(rules)?.group(1);

      expect(fn, isNotNull, reason: 'isAvailabilityOnlyChange() was removed');
      expect(fn, contains('request.resource.data.updatedAt == request.time'));
    });

    test('the updatedAt pin stays OFF the admin branch', () {
      // Deliberate asymmetry: pinning the admin branch too would make a legacy
      // doc holding a bad `updatedAt` un-updatable by the one role that can
      // repair it. The pin lives inside the self-only helper, so the admin
      // disjunct must not restate it.
      final updateBlock = RegExp(
        'allow update: if(.*?);',
        dotAll: true,
      ).firstMatch(rules)?.group(1);

      expect(
        updateBlock,
        isNot(contains('updatedAt == request.time')),
        reason: 'the pin belongs in isAvailabilityOnlyChange(), self-only',
      );
    });

    test('an email change is refused once an Auth account exists', () {
      // `email` is a sign-in identity: Auth and Firestore move together
      // through changeEmployeeEmail or not at all. Written directly on the
      // ADMIN branch it desyncs the two stores — the person signs in at the
      // old address while every admin surface shows the new one.
      final updateBlock = RegExp(
        'allow update: if(.*?);',
        dotAll: true,
      ).firstMatch(rules)?.group(1);
      expect(updateBlock, contains('emailMovesThroughAuth()'));

      final fn = RegExp(
        r'function emailMovesThroughAuth\(\)\s*\{(.*?)\n      \}',
        dotAll: true,
      ).firstMatch(rules)?.group(1);

      expect(fn, isNotNull, reason: 'emailMovesThroughAuth() was removed');
      // Diff-based: updateEmployee re-states the SAME email on every save, so
      // a flat ban would refuse every ordinary employee edit.
      expect(fn, contains("affectedKeys().hasAny(['email'])"));
      // And it exempts a doc with no Auth account to desync FROM.
      // changeEmployeeEmail refuses a uid-less doc outright
      // (`account-has-no-auth`), and updateEmployee's no-Auth branch is the
      // only writer left for a pre-P4c doc that never got one — a flat denial
      // would brick that doc's email with no path to repair it.
      expect(fn, contains("!('uid' in resource.data)"));
      expect(fn, contains("resource.data.uid == ''"));
    });

    test('the self allowlist never admits an escalation field', () {
      final fn = RegExp(
        r'function isAvailabilityOnlyChange\(\)\s*\{(.*?)\}',
        dotAll: true,
      ).firstMatch(rules)?.group(1);

      expect(fn, isNotNull);
      for (final banned in const [
        'role',
        'status',
        'uid',
        'colorValue',
        'maxJobsPerDay',
        'email',
      ]) {
        expect(
          fn,
          isNot(contains("'$banned'")),
          reason: '$banned must stay admin-only',
        );
      }
    });
  });
}
