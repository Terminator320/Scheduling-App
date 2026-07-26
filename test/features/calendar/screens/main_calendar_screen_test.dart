import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/screens/main_calendar_screen.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/l10n/l10n.dart';

class _MockEmployeesRepo extends Mock implements EmployeesRepository {}

const _jane = EmployeeRecord(
  id: 'e1',
  name: 'Jane Doe',
  email: 'jane@example.com',
  status: 'active',
);

AppointmentRecord _appointment(int id, DateTime day) => AppointmentRecord(
  id: 'a$id',
  title: 'Appt $id',
  startTime: day,
  endTime: day.add(const Duration(hours: 1)),
  clientId: 'c1',
  clientName: 'Alice',
  status: 'booked',
);

Widget _wrap({
  required Stream<List<AppointmentRecord>> appointments,
  required Stream<List<EmployeeRecord>> allUsers,
  required EmployeesRepository repo,
  bool isAdmin = true,
  double textScale = 1,
}) {
  return ProviderScope(
    overrides: [
      employeesRepositoryProvider.overrideWithValue(repo),
      currentUserNameProvider.overrideWithValue('Jane'),
      allUsersStreamProvider.overrideWith((_) => allUsers),
      appointmentsInRangeProvider.overrideWith((_, _) => appointments),
      myAppointmentsProvider.overrideWith((_, _) => appointments),
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
          child: child!,
        ),
        home: MainCalendar(isAdmin: isAdmin, employeeId: 'admin'),
      ),
    ),
  );
}

void main() {
  late _MockEmployeesRepo repo;

  setUp(() {
    repo = _MockEmployeesRepo();
  });

  // The calendar grid lays out at full phone width — size up to a real device
  // viewport so layout assertions don't trip on cosmetic overflow.
  Future<void> withPhoneViewport(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412 * 3, 915 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('renders Calendar AppBar title for an admin', (tester) async {
    await withPhoneViewport(tester);
    final day = DateTime(2026, 5, 16);
    await tester.pumpWidget(
      _wrap(
        appointments: Stream.value([_appointment(1, day)]),
        allUsers: Stream.value(const [_jane]),
        repo: repo,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Calendar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('icon-only controls expose localized tooltips', (tester) async {
    await withPhoneViewport(tester);
    await tester.pumpWidget(
      _wrap(
        appointments: Stream.value(const []),
        allUsers: Stream.value(const [_jane]),
        repo: repo,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Open menu'), findsOneWidget);
    expect(find.byTooltip('New Appointment'), findsOneWidget);
    expect(find.byTooltip('Today'), findsOneWidget);
  });

  testWidgets('month bar pluralizes the selected day appointment count', (
    tester,
  ) async {
    await withPhoneViewport(tester);
    // The initially selected day is today.
    final today = DateTime.now();
    await tester.pumpWidget(
      _wrap(
        appointments: Stream.value([_appointment(1, today)]),
        allUsers: Stream.value(const [_jane]),
        repo: repo,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 appointment'), findsOneWidget);
    expect(find.textContaining('1 appointments'), findsNothing);
  });

  testWidgets('month bar reserves room for its labels at 2x text scale', (
    tester,
  ) async {
    await withPhoneViewport(tester);
    await tester.pumpWidget(
      _wrap(
        appointments: Stream.value(const []),
        allUsers: Stream.value(const [_jane]),
        repo: repo,
        textScale: 2,
      ),
    );
    await tester.pumpAndSettle();

    final countLabel = find.text('0 appointments');
    expect(countLabel, findsOneWidget);

    // Reserved AppBar space below the toolbar must fit the scaled month-bar
    // text plus 8px padding, or labels get clipped (portrait toolbar height is kToolbarHeight).
    final appBarRect = tester.getRect(find.byType(AppBar));
    final reservedBottomSpace = appBarRect.height - kToolbarHeight;
    final textHeight = tester.getSize(countLabel).height;
    expect(reservedBottomSpace, greaterThanOrEqualTo(textHeight + 8));
    expect(tester.takeException(), isNull);
  });

  testWidgets('survives a stream error without crashing (error branch logs)', (
    tester,
  ) async {
    await withPhoneViewport(tester);
    await tester.pumpWidget(
      _wrap(
        appointments: Stream.error(StateError('boom')),
        allUsers: Stream.value(const [_jane]),
        repo: repo,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Calendar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
