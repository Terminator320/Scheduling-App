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
