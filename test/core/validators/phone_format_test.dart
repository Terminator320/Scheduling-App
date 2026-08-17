import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/validators/phone_format.dart';

TextEditingValue _type(String text) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: text.length),
);

void main() {
  group('formatPhoneNumber', () {
    test('formats a full North-American number', () {
      expect(formatPhoneNumber('5145551234'), '(514) 555-1234');
    });

    test('formats progressively while typing', () {
      expect(formatPhoneNumber('5'), '(5');
      expect(formatPhoneNumber('514'), '(514');
      expect(formatPhoneNumber('5145'), '(514) 5');
      expect(formatPhoneNumber('514555'), '(514) 555');
      expect(formatPhoneNumber('5145551'), '(514) 555-1');
    });

    test('is idempotent on already-formatted input', () {
      expect(formatPhoneNumber('(514) 555-1234'), '(514) 555-1234');
    });

    test('reformats a number typed with other separators', () {
      expect(formatPhoneNumber('514-555-1234'), '(514) 555-1234');
      expect(formatPhoneNumber('514.555.1234'), '(514) 555-1234');
    });

    test('empty stays empty', () {
      expect(formatPhoneNumber(''), '');
      expect(formatPhoneNumber('   '), '');
    });

    test('passes an international number through untouched', () {
      expect(formatPhoneNumber('+33 6 12 34 56 78'), '+33 6 12 34 56 78');
      expect(formatPhoneNumber('+15145551234'), '+15145551234');
    });

    test('keeps digits past the tenth instead of truncating', () {
      expect(formatPhoneNumber('5145551234567'), '(514) 555-1234 567');
    });
  });

  group('phoneDigits', () {
    test('strips every separator', () {
      expect(phoneDigits('(514) 555-1234'), '5145551234');
      expect(phoneDigits('+1 514 555 1234'), '15145551234');
    });
  });

  group('PhoneInputFormatter', () {
    const formatter = PhoneInputFormatter();

    test('formats as the user types and parks the caret at the end', () {
      final result = formatter.formatEditUpdate(_type('514'), _type('5145'));
      expect(result.text, '(514) 5');
      expect(result.selection.baseOffset, '(514) 5'.length);
    });

    test('leaves an unchanged value alone, caret included', () {
      // A no-op edit must not move the caret, or deleting mid-number would
      // yank the cursor to the end on every keystroke.
      const mid = TextEditingValue(
        text: '+33 6 12 34 56 78',
        selection: TextSelection.collapsed(offset: 4),
      );
      final result = formatter.formatEditUpdate(mid, mid);
      expect(result.selection.baseOffset, 4);
    });

    test('deleting a digit reformats down', () {
      final result = formatter.formatEditUpdate(
        _type('(514) 555-1234'),
        _type('(514) 555-123'),
      );
      expect(result.text, '(514) 555-123');
    });
  });

  group('bareNumber', () {
    test('takes the punctuation off a stored number', () {
      // `clients/{id}.name` is the Wave customer name, and the invoicing
      // workflow there wants the number unpunctuated.
      expect(bareNumber('(514) 555-1234'), '5145551234');
      expect(bareNumber('514-555-1234'), '5145551234');
    });

    test('keeps a leading + so an international number stays dialable', () {
      expect(bareNumber('+33 1 42 68 53 00'), '+33142685300');
    });

    test('keeps a leading country-code 1', () {
      // Unlike the comparison-only digit normalizer inside ClientNamePolicy,
      // this produces a value that gets STORED — dropping a digit the admin
      // typed would change the number.
      expect(bareNumber('1-514-555-1234'), '15145551234');
    });

    test('hands back anything it cannot reduce', () {
      expect(bareNumber('  ext. only  '), 'ext. only');
      expect(bareNumber(''), '');
    });
  });
}
