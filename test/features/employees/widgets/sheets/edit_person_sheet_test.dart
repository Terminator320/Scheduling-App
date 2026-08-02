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
import 'package:scheduling/features/employees/domain/policies/work_schedule_policy.dart';
import 'package:scheduling/features/employees/widgets/sheets/edit_person_sheet.dart';
import 'package:scheduling/l10n/l10n.dart';

class _MockRepo extends Mock implements EmployeesRepository {}

void main() {
  late _MockRepo repo;

  setUpAll(() {
    registerFallbackValue(const EmployeeRecord(id: 'fallback'));
  });

  setUp(() {
    repo = _MockRepo();
    // The sheet's body is a lazy scroll view, so a phone-sized viewport never
    // builds the availability panel or the footer. Every test but the scale
    // sweep runs tall enough to build the whole form at once.

    when(
      () => repo.updateEmployee(
        docId: any(named: 'docId'),
        employee: any(named: 'employee'),
      ),
    ).thenAnswer((_) async {});
  });

  /// Builds the whole lazy form at once so a below-the-fold row is findable.
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Widget wrap(
    EmployeeRecord employee, {
    Set<int> usedColors = const {},
    int futureAssignments = 0,
    bool offline = false,
    double textScale = 1,
  }) => ProviderScope(
    overrides: [
      employeesRepositoryProvider.overrideWithValue(repo),
      isOfflineProvider.overrideWithValue(offline),
      futureAssignmentCountProvider(
        employee.id,
      ).overrideWith((_) async => futureAssignments),
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
          body: EditPersonSheet(employee: employee, usedColors: usedColors),
        ),
      ),
    ),
  );

  /// The single EmployeeRecord the mocked repository received.
  EmployeeRecord capturedSave() =>
      verify(
            () => repo.updateEmployee(
              docId: any(named: 'docId'),
              employee: captureAny(named: 'employee'),
            ),
          ).captured.single
          as EmployeeRecord;

  void verifyNoSave() => verifyNever(
    () => repo.updateEmployee(
      docId: any(named: 'docId'),
      employee: any(named: 'employee'),
    ),
  );

  testWidgets('saving composes name from first and last', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(wrap(const EmployeeRecord(id: 'e1', name: 'Old')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('firstName')), 'Theo');
    await tester.enterText(find.byKey(const Key('lastName')), 'Roy');
    await tester.enterText(find.byKey(const Key('email')), 'theo@x.com');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(capturedSave().name, 'Theo Roy');
  });

  testWidgets('a legacy single-name doc seeds First and survives a save', (
    tester,
  ) async {
    useTallViewport(tester);
    await tester.pumpWidget(
      wrap(const EmployeeRecord(id: 'e1', name: 'Jean-Luc', email: 'j@x.com')),
    );
    await tester.pumpAndSettle();

    // Seeded, so the admin can actually see and edit the stored name.
    expect(find.text('Jean-Luc'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Never blank: watchAllUsers orders by name.
    expect(capturedSave().name, 'Jean-Luc');
  });

  testWidgets('an end at or before the start blocks Save', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(
      wrap(
        const EmployeeRecord(
          id: 'e1',
          name: 'Theo',
          email: 'theo@x.com',
          // Equal to the default start: an end that is not after it.
          workEndMinutes: kDefaultWorkStartMinutes,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Must be after start time'), findsOneWidget);
    verifyNoSave();
  });

  testWidgets('picking a job title does not touch the admin toggle', (
    tester,
  ) async {
    useTallViewport(tester);
    await tester.pumpWidget(
      wrap(const EmployeeRecord(id: 'e1', name: 'Theo', email: 'theo@x.com')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dispatcher'));
    await tester.pumpAndSettle();

    // jobTitle is what they do; role is what they can see. Never coupled.
    final adminSwitch = tester.widget<SwitchListTile>(
      find.byKey(const Key('adminAccess')),
    );
    expect(adminSwitch.value, isFalse);
  });

  testWidgets('max jobs per day is picked, and no cap saves as 0', (
    tester,
  ) async {
    useTallViewport(tester);
    await tester.pumpWidget(
      wrap(
        const EmployeeRecord(
          id: 'e1',
          name: 'Theo',
          email: 'theo@x.com',
          maxJobsPerDay: 5,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Renders the stored cap, not an empty field.
    expect(find.text('5'), findsOneWidget);

    await tester.tap(find.text('Max jobs per day'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No cap').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(capturedSave().maxJobsPerDay, 0);
  });

  testWidgets('shows how many colours are left', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(
      wrap(
        const EmployeeRecord(id: 'e1', name: 'Theo', email: 'theo@x.com'),
        usedColors: const {
          0xFF005CC8, // crewPalette[0]
          0xFF7A3FF2, // crewPalette[1]
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('8 colours left'), findsOneWidget);
  });

  testWidgets('shows the reassign count under Disable', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(
      wrap(
        const EmployeeRecord(id: 'e1', name: 'Theo', email: 'theo@x.com'),
        futureAssignments: 3,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('3 upcoming jobs stay assigned'),
      findsOneWidget,
    );
  });

  testWidgets('disabling asks for confirmation and calls the repository', (
    tester,
  ) async {
    when(() => repo.deactivateEmployee('e1')).thenAnswer((_) async {});

    useTallViewport(tester);
    await tester.pumpWidget(
      wrap(
        const EmployeeRecord(
          id: 'e1',
          name: 'Theo',
          email: 'theo@x.com',
          status: 'active',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Disable employee'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        "This employee will be signed out immediately and won't be able to "
        'log back in.',
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Disable employee'),
      ),
    );
    await tester.pumpAndSettle();

    verify(() => repo.deactivateEmployee('e1')).called(1);
    // The footer flips to the re-enable action without leaving the sheet.
    expect(find.text('Enable employee'), findsOneWidget);
  });

  testWidgets('offline save fails fast without calling the repository', (
    tester,
  ) async {
    useTallViewport(tester);
    await tester.pumpWidget(
      wrap(
        const EmployeeRecord(id: 'e1', name: 'Theo', email: 'theo@x.com'),
        offline: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    verifyNoSave();
  });

  testWidgets('survives 260x640 at 2.0 text scale', (tester) async {
    tester.view.physicalSize = const Size(260, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      wrap(
        const EmployeeRecord(id: 'e1', name: 'Theo', email: 'theo@x.com'),
        textScale: 2,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
