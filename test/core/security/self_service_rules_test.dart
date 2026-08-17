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
