import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/validators/text_limits.dart';

/// S2: `TextLimits` caps must be applied through
/// `LengthLimitingTextInputFormatter`, which truncates a too-long paste
/// rather than rejecting it outright.
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
    // Guards against a cap being bumped into the megabyte range, which
    // would blow past Firestore's 1 MiB doc-size ceiling.
    expect(TextLimits.appointmentTitle, lessThan(10000));
    expect(TextLimits.appointmentAddress, lessThan(10000));
    expect(TextLimits.appointmentNotes, lessThan(50000));
    expect(TextLimits.appointmentMaterials, lessThan(50000));
    expect(TextLimits.personName, lessThan(10000));
    expect(TextLimits.phone, lessThan(100));
    expect(TextLimits.email, lessThan(1000));
  });
}
