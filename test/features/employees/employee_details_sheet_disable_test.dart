import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/employees/widgets/employee_details_sheet.dart';
import 'package:scheduling/l10n/app_localizations.dart';

class _MockRepo extends Mock implements EmployeesRepository {}

const _activeEmployee = EmployeeRecord(
  id: 'e1',
  name: 'Jane Doe',
  email: 'jane@example.com',
  status: 'active',
  role: 'employee',
);

const _disabledEmployee = EmployeeRecord(
  id: 'e2',
  name: 'Bob Smith',
  email: 'bob@example.com',
  status: 'disabled',
  role: 'employee',
);

Widget _wrap(Widget child, {EmployeesRepository? repo}) {
  final mockRepo = repo ?? _MockRepo();
  return ProviderScope(
    overrides: [
      employeesRepositoryProvider.overrideWithValue(mockRepo),
    ],
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
        home: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  testWidgets('shows Disable button for admin viewing active employee',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        EmployeeDetailsSheet(
          employee: _activeEmployee,
          isCurrentUserAdmin: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Disable employee'), findsOneWidget);
    expect(find.text('Enable employee'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows Enable button for admin viewing disabled employee',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        EmployeeDetailsSheet(
          employee: _disabledEmployee,
          isCurrentUserAdmin: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Enable employee'), findsOneWidget);
    expect(find.text('Disable employee'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hides Disable/Enable button for non-admin',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        EmployeeDetailsSheet(
          employee: _activeEmployee,
          isCurrentUserAdmin: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Disable employee'), findsNothing);
    expect(find.text('Enable employee'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Disable tap shows confirmation dialog', (tester) async {
    await tester.pumpWidget(
      _wrap(
        EmployeeDetailsSheet(
          employee: _activeEmployee,
          isCurrentUserAdmin: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Disable employee'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disable employee'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        "This employee will be signed out immediately and won't be able to log back in.",
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Enable tap shows confirmation dialog', (tester) async {
    await tester.pumpWidget(
      _wrap(
        EmployeeDetailsSheet(
          employee: _disabledEmployee,
          isCurrentUserAdmin: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Enable employee'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enable employee'));
    await tester.pumpAndSettle();

    expect(
      find.text('This employee will be able to log back in.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
