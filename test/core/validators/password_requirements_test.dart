import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/validators/password_requirements.dart';

void main() {
  group('PasswordRequirement.minLength', () {
    test('is unmet below 8 characters', () {
      expect(PasswordRequirement.minLength.isMetBy('Aa1!567'), isFalse);
    });

    test('is met at 8 characters', () {
      expect(PasswordRequirement.minLength.isMetBy('Aa1!5678'), isTrue);
    });
  });

  group('PasswordRequirement.uppercase', () {
    test('is unmet without an uppercase letter', () {
      expect(PasswordRequirement.uppercase.isMetBy('abc123!@'), isFalse);
    });

    test('is met with an uppercase letter', () {
      expect(PasswordRequirement.uppercase.isMetBy('abcZ123!'), isTrue);
    });

    test('recognizes accented uppercase letters', () {
      expect(PasswordRequirement.uppercase.isMetBy('équipe123!'), isFalse);
      expect(PasswordRequirement.uppercase.isMetBy('Équipe123!'), isTrue);
    });
  });

  group('PasswordRequirement.lowercase', () {
    test('is unmet without a lowercase letter', () {
      expect(PasswordRequirement.lowercase.isMetBy('ABC123!@'), isFalse);
    });

    test('is met with a lowercase letter', () {
      expect(PasswordRequirement.lowercase.isMetBy('ABCz123!'), isTrue);
    });
  });

  group('PasswordRequirement.number', () {
    test('is unmet without a digit', () {
      expect(PasswordRequirement.number.isMetBy('Abcdefg!'), isFalse);
    });

    test('is met with a digit', () {
      expect(PasswordRequirement.number.isMetBy('Abcdefg7!'), isTrue);
    });
  });

  group('PasswordRequirement.symbol', () {
    test('is unmet without a symbol', () {
      expect(PasswordRequirement.symbol.isMetBy('Abcdefg7'), isFalse);
    });

    test('does not count whitespace as a symbol', () {
      expect(PasswordRequirement.symbol.isMetBy('Abcdef g7'), isFalse);
    });

    test('is met with a symbol', () {
      expect(PasswordRequirement.symbol.isMetBy('Abcdefg7#'), isTrue);
    });
  });

  group('PasswordRequirement.allMetBy', () {
    test('is false when any single rule is unmet', () {
      expect(PasswordRequirement.allMetBy('abcdef1!'), isFalse); // no upper
      expect(PasswordRequirement.allMetBy('ABCDEF1!'), isFalse); // no lower
      expect(PasswordRequirement.allMetBy('Abcdefg!'), isFalse); // no number
      expect(PasswordRequirement.allMetBy('Abcdefg1'), isFalse); // no symbol
      expect(PasswordRequirement.allMetBy('Abc1!'), isFalse); // too short
    });

    test('is true when every rule is met', () {
      expect(PasswordRequirement.allMetBy('Abcdef1!'), isTrue);
    });
  });
}
