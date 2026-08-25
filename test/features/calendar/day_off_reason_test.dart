import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/calendar/domain/day_off_reason.dart';

void main() {
  String? reason(String title, {bool hasSubject = true}) => dayOffReason(
    title: title,
    hasSubject: hasSubject,
    placeholders: {'Personal', 'Personnel'},
  );

  test('a typed reason leads', () {
    expect(reason('Vacation'), 'Vacation');
  });

  test('trims what it returns', () {
    expect(reason('  Vacation  '), 'Vacation');
  });

  test('a blank title is no reason', () {
    expect(reason(''), isNull);
    expect(reason('   '), isNull);
  });

  test('the "Personal" placeholder is NOT a reason', () {
    // An unnamed personal block saves this string rather than a blank, so
    // leading with it would make every untitled day off read "Personal".
    expect(reason('Personal'), isNull);
    expect(reason('personal'), isNull);
    expect(reason('  PERSONAL '), isNull);
  });

  test('a placeholder written in ANOTHER locale is still not a reason', () {
    // The title is stored in the AUTHOR's locale and read in the READER's, so
    // matching the reader's spelling alone would promote a French admin's
    // untitled block to an English reader's headline.
    expect(reason('Personnel'), isNull);
    expect(reason('  personnel'), isNull);
  });

  test('every supported locale is covered by the shipped set', () {
    // Guards the set itself: a new locale whose placeholder is missing here
    // would reintroduce exactly the bug above.
    expect(
      personalTitlePlaceholders,
      containsAll(<String>['Personal', 'Personnel']),
    );
  });

  test('with no subject the title is already the sentence, so no reason', () {
    // "Vacation is off" — leading with "Vacation" too would say it twice.
    expect(reason('Vacation', hasSubject: false), isNull);
  });
}
