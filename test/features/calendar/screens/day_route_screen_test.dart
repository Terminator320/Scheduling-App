import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/screens/day_route_screen.dart';
import 'package:scheduling/features/calendar/widgets/cards/appointment_card.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/app_empty_state.dart';

const _jane = EmployeeRecord(
  id: 'e1',
  name: 'Jane Doe',
  email: 'jane@example.com',
  status: 'active',
);

AppointmentRecord _job({
  required int id,
  required int hour,
  required String status,
  String address = '',
  List<String> employeeIds = const [],
  List<String> employeeNames = const [],
}) => AppointmentRecord(
  id: 'a$id',
  title: 'Appt $id',
  startTime: DateTime(2026, 5, 16, hour),
  endTime: DateTime(2026, 5, 16, hour + 1),
  status: status,
  address: address,
  employeeIds: employeeIds,
  employeeNames: employeeNames,
);

Widget _wrap({
  required List<AppointmentRecord> jobs,
  List<EmployeeRecord> employees = const [_jane],
  double textScale = 1,
}) {
  return ProviderScope(
    overrides: [
      myAppointmentsProvider.overrideWith((_, _) => Stream.value(jobs)),
      employeeColorMapProvider.overrideWithValue({
        for (final e in employees) e.id: e.color,
      }),
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
        home: const DayRouteScreen(isAdmin: false, employeeId: 'e1'),
      ),
    ),
  );
}

// Admin view: the picker is derived from the day's appointments (whole-day
// admin query) + the users name map, not the active-employee list.
Widget _adminScreen({
  required List<AppointmentRecord> dayJobs,
  Map<String, String> names = const {'e1': 'Jane Doe', 'e2': 'Bob Smith'},
  double textScale = 1,
}) => ProviderScope(
  overrides: [
    appointmentsInRangeProvider.overrideWith((_, _) => Stream.value(dayJobs)),
    employeeNameMapProvider.overrideWithValue(names),
    employeeColorMapProvider.overrideWithValue({
      for (final id in names.keys) id: const Color(0xFF2196F3),
    }),
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
      home: const DayRouteScreen(isAdmin: true, employeeId: 'admin'),
    ),
  ),
);

Future<void> _pump(
  WidgetTester tester,
  Widget widget, {
  Size size = const Size(412, 915),
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(widget);
  await tester.pumpAndSettle();
}

FilledButton _routeButton(WidgetTester tester) => tester.widget<FilledButton>(
  find.byWidgetPredicate((w) => w is FilledButton),
);

void main() {
  testWidgets('renders jobs sorted by start time regardless of input order', (
    tester,
  ) async {
    await _pump(
      tester,
      _wrap(
        jobs: [
          _job(id: 2, hour: 11, status: 'in_progress', address: '2 B St'),
          _job(id: 1, hour: 9, status: 'pending', address: '1 A St'),
          _job(id: 3, hour: 13, status: 'done', address: '3 C St'),
        ],
      ),
    );

    expect(find.byType(AppointmentCard), findsNWidgets(3));
    final y1 = tester.getTopLeft(find.text('Appt 1')).dy;
    final y2 = tester.getTopLeft(find.text('Appt 2')).dy;
    final y3 = tester.getTopLeft(find.text('Appt 3')).dy;
    expect(y1, lessThan(y2));
    expect(y2, lessThan(y3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelled jobs are excluded from the timeline', (tester) async {
    await _pump(
      tester,
      _wrap(
        jobs: [
          _job(id: 1, hour: 9, status: 'pending', address: '1 A St'),
          _job(id: 2, hour: 10, status: 'cancelled', address: '2 B St'),
        ],
      ),
    );

    expect(find.text('Appt 1'), findsOneWidget);
    expect(find.text('Appt 2'), findsNothing);
    expect(find.byType(AppointmentCard), findsOneWidget);
  });

  testWidgets('open stops numbered 1..N; done stop shows a check, no number', (
    tester,
  ) async {
    await _pump(
      tester,
      _wrap(
        jobs: [
          _job(id: 1, hour: 9, status: 'pending', address: '1 A St'),
          _job(id: 2, hour: 11, status: 'in_progress', address: '2 B St'),
          _job(id: 3, hour: 13, status: 'done', address: '3 C St'),
        ],
      ),
    );

    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsNothing); // done stop is not numbered
    expect(find.byIcon(Icons.check), findsOneWidget); // the done badge
  });

  testWidgets('navigate pill shows only for open stops that have an address', (
    tester,
  ) async {
    await _pump(
      tester,
      _wrap(
        jobs: [
          _job(id: 1, hour: 9, status: 'pending', address: '1 A St'),
          _job(id: 2, hour: 11, status: 'pending'), // open, no address
          _job(id: 3, hour: 13, status: 'done', address: '3 C St'), // done
        ],
      ),
    );

    // Only the first job is open AND has an address.
    expect(find.text('Navigate'), findsOneWidget);
    // Address-less open job is still numbered.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('empty day shows the empty state and disables the route button', (
    tester,
  ) async {
    await _pump(tester, _wrap(jobs: const []));

    expect(find.byType(AppEmptyState), findsOneWidget);
    expect(find.text('Open route in Google Maps (0)'), findsOneWidget);
    expect(_routeButton(tester).onPressed, isNull);
  });

  testWidgets('route button disabled when open stops lack addresses', (
    tester,
  ) async {
    await _pump(
      tester,
      _wrap(
        jobs: [_job(id: 1, hour: 9, status: 'pending')], // open, no address
      ),
    );

    expect(find.byType(AppointmentCard), findsOneWidget); // still listed
    expect(find.text('Open route in Google Maps (0)'), findsOneWidget);
    expect(_routeButton(tester).onPressed, isNull);
  });

  testWidgets('route button enabled and counts addressed open stops', (
    tester,
  ) async {
    await _pump(
      tester,
      _wrap(
        jobs: [
          _job(id: 1, hour: 9, status: 'pending', address: '1 A St'),
          _job(id: 2, hour: 11, status: 'in_progress', address: '2 B St'),
          _job(id: 3, hour: 13, status: 'done', address: '3 C St'), // excluded
        ],
      ),
    );

    expect(find.text('Open route in Google Maps (2)'), findsOneWidget);
    expect(_routeButton(tester).onPressed, isNotNull);
  });

  testWidgets('admin picker lists only employees with a job that day', (
    tester,
  ) async {
    await _pump(
      tester,
      _adminScreen(
        dayJobs: [
          _job(
            id: 1,
            hour: 9,
            status: 'pending',
            address: '1 A St',
            employeeIds: const ['e1'],
          ),
        ],
      ),
    );

    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    // Jane has the job → listed; Bob has none that day → absent.
    expect(find.text('Jane Doe'), findsWidgets);
    expect(find.text('Bob Smith'), findsNothing);
    // The selected assignee's job renders in the timeline.
    expect(find.text('Appt 1'), findsOneWidget);
  });

  testWidgets('no admin picker when the day has no jobs', (tester) async {
    await _pump(tester, _adminScreen(dayJobs: const []));

    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.byType(AppEmptyState), findsOneWidget);
  });

  testWidgets('no employee picker for a non-admin', (tester) async {
    await _pump(
      tester,
      _wrap(
        jobs: [_job(id: 1, hour: 9, status: 'pending', address: '1 A St')],
      ),
    );

    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
  });

  testWidgets('no overflow at 375x667 with 2x text scale', (tester) async {
    await _pump(
      tester,
      _wrap(
        textScale: 2,
        jobs: [
          _job(id: 1, hour: 9, status: 'pending', address: '1 A St'),
          _job(id: 2, hour: 11, status: 'done', address: '2 B St'),
        ],
      ),
      size: const Size(375, 667),
    );

    expect(tester.takeException(), isNull);
  });
}
