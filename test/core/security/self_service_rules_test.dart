import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// P5's self-service clause. `isAvailabilityOnlyChange()` was written in P4 and
/// deliberately left uncalled until there was a UI behind it; this pins the
/// call, and pins the two things that make it safe to grant.
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
      // The disjunction must be parenthesized.
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
      // revokes it, and an invited one is mid-setup.
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
      // with no bound at all.
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
      // repair it.
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
      // `email` is a sign-in identity: Auth and Firestore move together through
      // changeEmployeeEmail or not at all.
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
      // Diff-based: updateEmployee re-states the SAME email on every save, so a
      // flat ban would refuse every ordinary employee edit.
      expect(fn, contains("affectedKeys().hasAny(['email'])"));
      // And it exempts a doc with no Auth account to desync FROM.
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
