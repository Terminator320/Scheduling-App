import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/employees/screens/employees_screen.dart';
import 'package:scheduling/l10n/app_localizations.dart';

const _jane = EmployeeRecord(
  id: 'e1',
  name: 'Jane Doe',
  email: 'jane@example.com',
  status: 'active',
  role: 'employee',
);

const _bob = EmployeeRecord(
  id: 'e2',
  name: 'Bob Smith',
  email: 'bob@example.com',
  status: 'active',
  role: 'employee',
);

Widget _wrap({required Stream<List<EmployeeRecord>> employees}) {
  return ProviderScope(
    overrides: [employeesStreamProvider.overrideWith((_) => employees)],
    child: ThemeNotifier(
      themeMode: ThemeMode.light,
      toggleTheme: () {},
      textScale: 1.0,
      setTextScale: (_) {},
      setLanguage: (_) {},
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: lightTheme(),
        home: const AddEmployeePage(isAdmin: true, employeeId: 'admin'),
      ),
    ),
  );
}

void main() {
  testWidgets('renders employee cards from the stream', (tester) async {
    await tester.pumpWidget(
      _wrap(employees: Stream.value(const [_jane, _bob])),
    );
    await tester.pumpAndSettle();

    expect(find.text('Jane Doe'), findsOneWidget);
    expect(find.text('Bob Smith'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows empty-state copy when the list is empty', (tester) async {
    await tester.pumpWidget(_wrap(employees: Stream.value(const [])));
    await tester.pumpAndSettle();

    expect(find.textContaining('No employees'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows error copy when the stream errors', (tester) async {
    await tester.pumpWidget(_wrap(employees: Stream.error(StateError('boom'))));
    await tester.pumpAndSettle();

    expect(find.textContaining('rror'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
