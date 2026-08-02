import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/connectivity/connectivity_providers.dart';
import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/employees/application/employee_schedule_providers.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/employees/domain/models/job_title.dart';
import 'package:scheduling/features/employees/widgets/cards/employee_card.dart';
import 'package:scheduling/features/employees/widgets/sheets/edit_person_sheet.dart';
import 'package:scheduling/features/employees/widgets/sheets/invite_person_sheet.dart';
import 'package:scheduling/features/employees/widgets/views/employee_details_view.dart';
import 'package:scheduling/l10n/l10n.dart';

class _MockRepo extends Mock implements EmployeesRepository {}

const _employee = EmployeeRecord(
  id: 'e1',
  name: 'Theo Roy',
  firstName: 'Theo',
  lastName: 'Roy',
  email: 'theo@example.com',
  phone: '514-555-0100',
  role: 'admin',
  status: 'active',
  jobTitle: JobTitle.leadTech,
  maxJobsPerDay: 4,
  onCall: true,
  emergencyContact: 'Marie 514-555-0199',
);

/// 375x667 is the reference phone; the sweep runs the redesigned Team surfaces
/// across the text scales the app itself offers (the in-app XL setting is
/// exactly 1.4) plus the OS extreme.
const _scales = [0.8, 1.0, 1.4, 2.0];

Widget _wrap(Widget child, double scale) => ProviderScope(
  overrides: [
    employeesRepositoryProvider.overrideWithValue(_MockRepo()),
    isOfflineProvider.overrideWithValue(false),
    employeeJobsTodayProvider.overrideWithValue(const {'e1': 3}),
    employeeTodayJobsProvider('e1').overrideWithValue(const []),
    futureAssignmentCountProvider('e1').overrideWith((_) async => 2),
  ],
  child: ThemeNotifier(
    themeMode: ThemeMode.light,
    toggleTheme: () {},
    textScale: scale,
    setTextScale: (_) {},
    setLanguage: (_) {},
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: lightTheme(),
      builder: (context, inner) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: inner ?? const SizedBox.shrink(),
      ),
      home: Scaffold(body: child),
    ),
  ),
);

void main() {
  setUpAll(() {
    registerFallbackValue(const EmployeeRecord(id: 'fallback'));
  });

  Future<void> sweep(
    WidgetTester tester,
    Widget Function() build, {
    // The two form sheets are lazy scroll views; a short viewport simply does
    // not build their lower half, so they sweep tall enough to lay all of it
    // out at once. The roster row and the detail view fit the reference phone.
    bool tall = false,
  }) async {
    for (final scale in _scales) {
      tester.view.physicalSize = tall
          ? const Size(375, 2400)
          : const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(build(), scale));
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: 'overflowed at text scale $scale',
      );
    }
  }

  testWidgets('roster row survives every text scale', (tester) async {
    await sweep(
      tester,
      () => EmployeeCard(employee: _employee, onTap: () {}),
    );
  });

  testWidgets('detail view survives every text scale', (tester) async {
    await sweep(
      tester,
      () => EmployeeDetailsView(
        employee: _employee,
        isCurrentUserAdmin: true,
        onEdit: () {},
      ),
    );
  });

  testWidgets('edit sheet survives every text scale', (tester) async {
    await sweep(
      tester,
      () => const EditPersonSheet(employee: _employee),
      tall: true,
    );
  });

  testWidgets('invite sheet survives every text scale', (tester) async {
    await sweep(tester, () => const InvitePersonSheet(), tall: true);
  });
}
