import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/employees/application/employee_schedule_providers.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/features/employees/domain/models/emergency_contact.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/employees/domain/models/job_title.dart';
import 'package:scheduling/features/employees/widgets/cards/employee_profile_card.dart';
import 'package:scheduling/features/employees/widgets/sections/employee_today_section.dart';
import 'package:scheduling/features/employees/widgets/views/employee_details_view.dart';
import 'package:scheduling/l10n/l10n.dart';

class _MockRepo extends Mock implements EmployeesRepository {}

const _populated = EmployeeRecord(
  id: 'e1',
  name: 'Theo Roy',
  email: 'theo@x.com',
  phone: '555-0100',
  role: 'admin',
  status: 'active',
  jobTitle: JobTitle.leadTech,
  maxJobsPerDay: 4,
);

Widget _wrap(
  EmployeeRecord employee, {
  required bool isCurrentUserAdmin,
  double textScale = 1,
  Stream<EmergencyContact>? emergency,
}) => ProviderScope(
  overrides: [
    employeesRepositoryProvider.overrideWithValue(_MockRepo()),
    employeeTodayJobsProvider(employee.id).overrideWithValue(const []),
    if (emergency != null)
      emergencyContactProvider(employee.id).overrideWith((ref) => emergency),
  ],
  child: ThemeNotifier(
    themeMode: ThemeMode.light,
    toggleTheme: () {},
    textScale: textScale,
    setTextScale: (_) {},
    setLanguage: (_) {},
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: lightTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child ?? const SizedBox.shrink(),
      ),
      home: Scaffold(
        body: EmployeeDetailsView(
          employee: employee,
          isCurrentUserAdmin: isCurrentUserAdmin,
          onEdit: () {},
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('shows the profile card, info panel and today panel', (
    tester,
  ) async {
    // Tall enough to build all three panels at once: EMERGENCY is its own
    // panel between the info block and Today, so at the default 800x600 the
    // today panel falls outside the lazy list's build window.
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(_populated, isCurrentUserAdmin: true));
    await tester.pumpAndSettle();

    expect(find.byType(EmployeeProfileCard), findsOneWidget);
    expect(find.text('PHONE'), findsOneWidget);
    expect(find.text('ACCESS'), findsOneWidget);
    expect(find.byType(EmployeeTodaySection), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders working hours with a clean ASCII separator', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_populated, isCurrentUserAdmin: true));
    await tester.pumpAndSettle();

    expect(find.textContaining(' - '), findsOneWidget);
  });

  testWidgets('omits rows with no value', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const EmployeeRecord(id: 'e1', name: 'Theo Roy', status: 'active'),
        isCurrentUserAdmin: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PHONE'), findsNothing);
    expect(find.text('EMAIL'), findsNothing);
    expect(find.text('EMERGENCY'), findsNothing);
    expect(find.text('MAX/DAY'), findsNothing);
    // HOURS and ACCESS always render — every employee has both.
    expect(find.text('HOURS'), findsOneWidget);
    expect(find.text('ACCESS'), findsOneWidget);
  });

  testWidgets('a non-admin viewer gets no Edit pill', (tester) async {
    await tester.pumpWidget(_wrap(_populated, isCurrentUserAdmin: false));
    await tester.pumpAndSettle();

    expect(find.text('Edit'), findsNothing);
    // The rest of the page is still readable.
    expect(find.byType(EmployeeProfileCard), findsOneWidget);
  });

  testWidgets('profile card falls back to the split name when name is blank', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const EmployeeRecord(
          id: 'e1',
          firstName: 'Amy',
          lastName: 'Adams',
          email: 'amy@shop.ca',
          status: 'active',
        ),
        isCurrentUserAdmin: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Amy Adams'), findsOneWidget);
  });

  testWidgets('shows the emergency panel when a contact is on file', (
    tester,
  ) async {
    // The pair lives in users/{id}/private/emergency precisely so rules can
    // gate it — this view is the admin-side surface that renders it.
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrap(
        _populated,
        isCurrentUserAdmin: true,
        emergency: Stream.value(
          const EmergencyContact(contact: 'Mia Roy', phone: '555-0199'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('EMERGENCY PHONE'), findsOneWidget);
    expect(find.text('Mia Roy'), findsOneWidget);
    expect(find.text('555-0199'), findsOneWidget);
  });

  testWidgets('a failed emergency read shows nothing, not a placeholder', (
    tester,
  ) async {
    // Loading and error deliberately render the same "not shown" on this
    // read-only surface; the provider logs the failure itself.
    await tester.pumpWidget(
      _wrap(
        _populated,
        isCurrentUserAdmin: true,
        emergency: Stream.error(StateError('denied')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('EMERGENCY'), findsNothing);
    expect(find.text('EMERGENCY PHONE'), findsNothing);
  });

  testWidgets('survives 260x640 at 2.0 text scale', (tester) async {
    tester.view.physicalSize = const Size(260, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrap(_populated, isCurrentUserAdmin: true, textScale: 2),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
