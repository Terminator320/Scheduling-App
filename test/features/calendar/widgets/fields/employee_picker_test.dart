import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/calendar/widgets/fields/employee_picker.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/l10n/l10n.dart';

/// "Only active staff are offered" is the premise the whole
/// `mergeRetainedAssignees` invariant rests on: because a disabled assignee
/// never renders a chip, they cannot be deselected, which is why saving must
/// re-append the original assignees missing from the active set.
EmployeeRecord _employee(String id, String name) => EmployeeRecord(
  id: id,
  name: name,
  email: '$id@example.com',
  status: 'active',
);

Future<void> _pump(
  WidgetTester tester, {
  required List<EmployeeRecord> allEmployees,
  required List<EmployeeRecord> selectedEmployees,
  bool selectable = true,
  void Function(EmployeeRecord)? onToggle,
}) => tester.pumpWidget(
  MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: EmployeePicker(
        allEmployees: allEmployees,
        selectedEmployees: selectedEmployees,
        selectable: selectable,
        onToggle: onToggle,
      ),
    ),
  ),
);

void main() {
  final active = _employee('e1', 'Ada Lovelace');
  final disabled = _employee('e2', 'Grace Hopper');

  testWidgets('every active employee is offered', (tester) async {
    await _pump(
      tester,
      allEmployees: [active],
      selectedEmployees: const [],
    );

    expect(find.text('Ada'), findsOneWidget);
  });

  testWidgets('an assignee missing from the active set is not offered', (
    tester,
  ) async {
    await _pump(
      tester,
      allEmployees: [active],
      selectedEmployees: [active, disabled],
    );

    expect(find.text('Grace'), findsNothing);
  });

  testWidgets('a disabled assignee therefore cannot be deselected', (
    tester,
  ) async {
    final toggled = <String>[];
    await _pump(
      tester,
      allEmployees: [active],
      selectedEmployees: [active, disabled],
      onToggle: (e) => toggled.add(e.id),
    );
    await tester.tap(find.text('Ada'));
    await tester.pumpAndSettle();

    expect(toggled, ['e1']);
  });

  testWidgets('the read-only picker shows assignees only', (tester) async {
    await _pump(
      tester,
      allEmployees: [active, _employee('e3', 'Alan Turing')],
      selectedEmployees: [active],
      selectable: false,
    );

    expect(find.text('Alan'), findsNothing);
  });
}
