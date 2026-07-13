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
}) => AppointmentRecord(
  id: 'a$id',
  title: 'Appt $id',
  startTime: DateTime(2026, 5, 16, hour),
  endTime: DateTime(2026, 5, 16, hour + 1),
  status: status,
  address: address,
);

Widget _wrap({
  required List<AppointmentRecord> jobs,
  List<EmployeeRecord> employees = const [_jane],
  bool isAdmin = false,
  double textScale = 1,
}) {
  return ProviderScope(
    overrides: [
      myAppointmentsProvider.overrideWith((_, _) => Stream.value(jobs)),
      employeesStreamProvider.overrideWith((_) => Stream.value(employees)),
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

// The screen is admin-gated via the widget arg, so build a wrapper whose home
// uses the requested isAdmin/textScale (the top-level _wrap fixes isAdmin:false
// so most tests read the employee view directly).
Widget _screen({required bool isAdmin, double textScale = 1}) => ProviderScope(
  overrides: [
    myAppointmentsProvider.overrideWith((_, _) => Stream.value(const [])),
    employeesStreamProvider.overrideWith((_) => Stream.value(const [_jane])),
    employeeColorMapProvider.overrideWithValue({'e1': _jane.color}),
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
      home: DayRouteScreen(isAdmin: isAdmin, employeeId: 'e1'),
    ),
  ),
);

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

  testWidgets('admin picker visible only for admins', (tester) async {
    await _pump(tester, _screen(isAdmin: true));
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    expect(find.text('Employee'), findsWidgets);

    await _pump(tester, _screen(isAdmin: false));
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
