import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/validators/text_limits.dart';

/// S2: `TextLimits` caps must be applied through
/// `LengthLimitingTextInputFormatter`. This test verifies the formatter
/// behaviour the forms rely on — a paste longer than the cap is truncated,
/// not rejected wholesale.
void main() {
  test('LengthLimitingTextInputFormatter truncates to cap', () {
    final formatter = LengthLimitingTextInputFormatter(
      TextLimits.appointmentTitle,
    );
    final tooLong = 'x' * (TextLimits.appointmentTitle + 50);

    final result = formatter.formatEditUpdate(
      TextEditingValue.empty,
      TextEditingValue(
        text: tooLong,
        selection: TextSelection.collapsed(offset: tooLong.length),
      ),
    );

    expect(result.text.length, TextLimits.appointmentTitle);
  });

  test('caps stay within Firestore safe ranges', () {
    // Sanity check: every cap should leave room for many documents under
    // Firestore's 1 MiB doc-size ceiling. If anyone bumps a cap into the
    // megabyte range, this fails noisily.
    expect(TextLimits.appointmentTitle, lessThan(10000));
    expect(TextLimits.appointmentAddress, lessThan(10000));
    expect(TextLimits.appointmentNotes, lessThan(50000));
    expect(TextLimits.appointmentMaterials, lessThan(50000));
    expect(TextLimits.personName, lessThan(10000));
    expect(TextLimits.phone, lessThan(100));
    expect(TextLimits.email, lessThan(1000));
  });
}
