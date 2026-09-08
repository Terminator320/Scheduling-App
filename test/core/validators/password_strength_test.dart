import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/validators/password_strength.dart';

void main() {
  test('scores an empty password 0', () {
    expect(passwordStrengthScore(''), 0);
  });

  test('scores a short single-case password 0', () {
    // Fails length, mixed case and digit alike.
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

  test('a compliant password without a symbol can still reach Strong', () {
    // The meter renders four segments and gates "Strong" on 4, so the top
    // band has to be reachable by a password the validator actually accepts.
    expect(passwordStrengthScore('Passw0rdAbcd'), 4);
  });

  test('withholds both length bands from a short strong password', () {
    // 'Aa1!' meets case and number but is short of both the 8-char minLength
    // band and the 12-char bonus band, so it scores 2, not 3.
    expect(passwordStrengthScore('Aa1!'), 2);
  });

  test('never exceeds 4', () {
    expect(passwordStrengthScore(r'AaBb11!!##$$Zz'), 4);
  });

  test('the bonus band is length, not a symbol', () {
    // Eight characters with a symbol used to score 4; it must not any more.
    expect(passwordStrengthScore('Passw0r!'), 3);
  });
}
