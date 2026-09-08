import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/validators/email_format.dart';

/// `normalizeEmail` is the only invariant owner CLAUDE.md names by name that
/// had no test.
///
/// It is one line, which is exactly why it is worth pinning: every read and
/// write that keys on an address goes through it, and `users.email` is an
/// employee's SIGN-IN identity. If the two halves ever disagree with the
/// stored form, a lookup misses a doc that is really there — the account looks
/// deleted, or a uniqueness check passes on an address already taken. Nothing
/// throws; the query just comes back empty.
void main() {
  group('normalizeEmail', () {
    test('trims and lowercases, the two halves together', () {
      expect(normalizeEmail('  Jane@Example.com '), 'jane@example.com');
    });

    test('is idempotent — normalizing twice changes nothing', () {
      // Callers normalize defensively at more than one layer; a second pass
      // must not alter what the first produced.
      const raw = '  Jane@Example.COM\t';
      final once = normalizeEmail(raw);
      expect(normalizeEmail(once), once);
    });

    test('strips every flavour of surrounding whitespace', () {
      // A pasted address is the realistic source, and it can arrive with a
      // tab, a newline or a non-breaking run of spaces around it.
      for (final raw in [
        ' jane@example.com',
        'jane@example.com ',
        '\tjane@example.com\n',
        '\r\n jane@example.com \r\n',
      ]) {
        expect(normalizeEmail(raw), 'jane@example.com');
      }
    });

    test('leaves INNER characters alone, including spaces', () {
      // It is a normalizer, not a validator: rejecting a malformed address is
      // someone else's job, and quietly repairing one here would make two
      // different inputs collide on one identity.
      expect(normalizeEmail(' A B@x.com '), 'a b@x.com');
      expect(normalizeEmail('a+tag@x.com'), 'a+tag@x.com');
      expect(normalizeEmail('A.B.C@X.CO.UK'), 'a.b.c@x.co.uk');
    });

    test('handles the empty and whitespace-only cases without throwing', () {
      expect(normalizeEmail(''), '');
      expect(normalizeEmail('   '), '');
    });

    test('lowercases non-ASCII too, so an accented local part still matches',
        () {
      expect(normalizeEmail('  RENÉ@Example.CA '), 'rené@example.ca');
    });
  });
}
