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
      textScale: 1,
      setTextScale: (_) {},
      setLanguage: (_) {},
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: lightTheme(),
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

  // The calendar grid lays out at full phone width; the default 800×600
  // test viewport overflows by a couple of pixels. Size up to match a real
  // device so layout assertions don't trip on cosmetic overflow.
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
