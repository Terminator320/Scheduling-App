import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/validators/password_strength.dart';

void main() {
  test('scores an empty password 0', () {
    expect(passwordStrengthScore(''), 0);
  });

  test('scores a short single-case password 0', () {
    // Fails length, mixed case, digit and symbol alike.
    expect(passwordStrengthScore('abc'), 0);
  });

  test('scores length alone 1', () {
    expect(passwordStrengthScore('aaaaaaaa'), 1);
  });

  test('counts mixed case as exactly one band', () {
    expect(passwordStrengthScore('Aaaaaaaa'), 2);
  });

  test('scores length, case and a digit 3', () {
    expect(passwordStrengthScore('Aaaaaaa1'), 3);
  });

  test('scores a password meeting every band 4', () {
    expect(passwordStrengthScore('Aa1!aaaa'), 4);
  });

  test('withholds the length band from a short strong password', () {
    expect(passwordStrengthScore('Aa1!'), 3);
  });

  test('never exceeds 4', () {
    expect(passwordStrengthScore(r'AaBb11!!##$$Zz'), 4);
  });
}
