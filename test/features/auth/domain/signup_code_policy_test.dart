import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/auth/domain/signup_code_policy.dart';

void main() {
  group('normalizeSignupCode', () {
    test('strips the grouping dashes and uppercases', () {
      expect(normalizeSignupCode('k7q2-9mz4-xr8t'), 'K7Q29MZ4XR8T');
    });

    test('strips spaces and stray separators a paste can carry', () {
      expect(normalizeSignupCode(' K7Q2 9MZ4\t9R8T '), 'K7Q29MZ49R8T');
    });

    test('leaves an already-canonical code untouched', () {
      expect(normalizeSignupCode('K7Q29MZ4XR8T'), 'K7Q29MZ4XR8T');
    });

    test('does NOT alias I to 1 or O to 0 — the server does no aliasing', () {
      expect(normalizeSignupCode('IO'), 'IO');
    });

    test('an empty string normalizes to empty', () {
      expect(normalizeSignupCode('   '), '');
    });
  });

  group('isCompleteSignupCode', () {
    test('a full dashed code is complete', () {
      expect(isCompleteSignupCode('K7Q2-9MZ4-XR8T'), isTrue);
    });

    test('eleven characters is not complete', () {
      expect(isCompleteSignupCode('K7Q2-9MZ4-XR8'), isFalse);
    });

    test('thirteen characters is not complete', () {
      expect(isCompleteSignupCode('K7Q2-9MZ4-XR8TZ'), isFalse);
    });

    test('the expected length is twelve', () {
      expect(kSignupCodeLength, 12);
    });
  });
}
