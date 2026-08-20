import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The emergency contact names a THIRD PARTY who is not an app user and never
/// consented, and `/users` is readable by every active peer — so a value must
/// never be able to land on that doc. The pair lives in
/// `users/{docId}/private/emergency` instead.
///
/// Rules cannot be unit-tested without the emulator, so this reads
/// `firestore.rules` back as text. That is the same mechanism
/// `text_limits_test.dart` uses to turn a written-down rule into an enforced
/// one — weaker than an emulator suite, but it does catch the specific
/// regression that matters here: someone "simplifying" the guard away, or
/// collapsing it into the plain denylist beside `uid`.
void main() {
  late final rules = File('firestore.rules').readAsStringSync();

  group(
    'emergency contact cannot be written to the peer-readable users doc',
    () {
      test('allow update routes both fields through emergencyFieldNotSet', () {
        expect(rules, contains("emergencyFieldNotSet('emergencyContact')"));
        expect(rules, contains("emergencyFieldNotSet('emergencyPhone')"));
      });

      test('the guard permits removal and forbids a value', () {
        // Two halves, and both are load-bearing: `affectedKeys` untouched means
        // a legacy value passes through so the doc stays updatable, and the
        // `!(f in request.resource.data)` half is what makes a *set* impossible.
        final guard = RegExp(
          r'function emergencyFieldNotSet\(f\)\s*\{(.*?)\}',
          dotAll: true,
        ).firstMatch(rules)?.group(1);

        expect(guard, isNotNull, reason: 'emergencyFieldNotSet was removed');
        expect(guard, contains('affectedKeys'));
        expect(guard, contains('!(f in request.resource.data)'));
      });

      test('both fields stay on the allow-create denylist', () {
        // Create has no legacy doc to protect, so there it is an outright ban.
        final createBlock = RegExp(
          r'allow create: if isAdmin\(\)(.*?);',
          dotAll: true,
        ).firstMatch(rules)?.group(1);

        expect(createBlock, isNotNull);
        expect(createBlock, contains('emergencyContact'));
        expect(createBlock, contains('emergencyPhone'));
      });

      test('the legacy caps survive with their exact bounds', () {
        // These two caps only ever see a LEGACY value passing through
        // untouched on an unrelated update — no write path can introduce one
        // any more. That is precisely what makes them look unreachable and
        // invites deletion, and the rules comment says so in as many words.
        // Delete them and a straggler doc becomes permanently un-updatable,
        // including by deactivateEmployee.
        //
        // SCOPED to /users and then to isValidUserData: `isBoundedString` is
        // used all over this file, and an unscoped search would pass on some
        // other block's cap. The numbers are asserted, not just the field
        // names — a cap whose bound drifted below a stored value bricks the
        // doc exactly as removing it does.
        final users = rules.substring(rules.indexOf('match /users/{userId}'));
        final shapeGuard = RegExp(
          r'function isValidUserData\(d\)\s*\{(.*?)\n      \}',
          dotAll: true,
        ).firstMatch(users)?.group(1);

        expect(shapeGuard, isNotNull, reason: 'isValidUserData was removed');
        expect(
          shapeGuard,
          contains('isBoundedString(d.emergencyContact, 200)'),
        );
        expect(shapeGuard, contains('isBoundedString(d.emergencyPhone, 40)'));
        // Both are guarded by a key-presence check, so an ordinary doc that
        // never carried the pair still validates.
        expect(shapeGuard, contains("!('emergencyContact' in d.keys())"));
        expect(shapeGuard, contains("!('emergencyPhone' in d.keys())"));
      });

      test('both create and the self-update branch run isValidUserData', () {
        // The caps are only worth anything if the shape guard is actually
        // reached. Scoped to /users for the same reason as above.
        final users = rules.substring(rules.indexOf('match /users/{userId}'));

        // The call form, not the bare name — the name also appears in three
        // explanatory comments in this file.
        expect(
          RegExp(
            r'isValidUserData\(request\.resource\.data\)',
          ).allMatches(users).length,
          greaterThanOrEqualTo(2),
          reason: 'isValidUserData is no longer wired into both write branches',
        );
      });

      test('the private/emergency subcollection is gated to admin + self', () {
        final block = RegExp(
          r'match /private/emergency \{(.*?)\n      \}',
          dotAll: true,
        ).firstMatch(rules)?.group(1);

        expect(block, isNotNull, reason: 'private/emergency block was removed');
        // A peer must never reach it — that is the entire reason for the move.
        expect(block, contains('myDocId() == userId'));
        expect(block, contains('isAdmin()'));
      });
    },
  );
}
