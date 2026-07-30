import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/calendar/domain/collapse_state.dart';

void main() {
  test('collapses only past 80px', () {
    final collapse = CalendarCollapse();
    expect(collapse.onOffset(79), isFalse);
    expect(collapse.isCollapsed, isFalse);
    expect(collapse.onOffset(81), isTrue);
    expect(collapse.isCollapsed, isTrue);
  });

  test('a jump straight to the top still re-expands', () {
    // A "scroll to top" jumps past every intermediate frame, so arming and
    // firing have to be able to happen in the same pass.
    final collapse = CalendarCollapse()..onOffset(200);
    expect(collapse.onOffset(0), isTrue);
    expect(collapse.isCollapsed, isFalse);
  });

  test('arms below 44 then expands below 6', () {
    final collapse = CalendarCollapse()..onOffset(200);
    expect(collapse.onOffset(40), isFalse);
    expect(collapse.onOffset(5), isTrue);
    expect(collapse.isCollapsed, isFalse);
  });

  test('reaching the arm threshold is not enough on its own', () {
    final collapse = CalendarCollapse()..onOffset(200);
    expect(collapse.onOffset(20), isFalse);
    expect(collapse.isCollapsed, isTrue);
  });

  test('reports a transition only once per crossing', () {
    final collapse = CalendarCollapse();
    expect(collapse.onOffset(120), isTrue);
    expect(collapse.onOffset(130), isFalse);
    expect(collapse.onOffset(140), isFalse);
  });

  test('hovering the collapse threshold does not thrash', () {
    final collapse = CalendarCollapse();
    expect(collapse.onOffset(81), isTrue);
    // Back to 70 must NOT expand — it armed at 200+ only in the other test,
    // and here it has never dropped below 6.
    expect(collapse.onOffset(70), isFalse);
    expect(collapse.onOffset(45), isFalse);
    expect(collapse.isCollapsed, isTrue);
  });

  test('a full collapse and re-expand cycle can repeat', () {
    final collapse = CalendarCollapse();
    for (var i = 0; i < 3; i++) {
      expect(collapse.onOffset(200), isTrue, reason: 'collapse pass $i');
      expect(collapse.onOffset(0), isTrue, reason: 'expand pass $i');
    }
  });
}
