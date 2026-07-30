import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/screens/main_calendar_screen.dart';
import 'package:scheduling/features/calendar/widgets/views/calendar_header_block.dart';
import 'package:scheduling/features/calendar/widgets/views/calendar_month_pager.dart';
import 'package:scheduling/features/calendar/widgets/views/calendar_week_strip.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/app_bars/app_header_pair.dart';

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

  testWidgets('renders the fixed header block for an admin', (tester) async {
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

    // The calendar is the one screen without an AppTopBar — its header block
    // hosts the pair instead, so the only "Calendar" text is the go-home pill.
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(CalendarHeaderBlock), findsOneWidget);
    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('SCHEDULE'), findsOneWidget);
    expect(find.byType(AppHeaderPair), findsOneWidget);
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

  testWidgets('the Today pill hides while today is the day on screen', (
    tester,
  ) async {
    await withPhoneViewport(tester);
    await tester.pumpWidget(
      _wrap(
        appointments: Stream.value(const []),
        allUsers: Stream.value(const [_jane]),
        repo: repo,
      ),
    );
    await tester.pumpAndSettle();

    // The pill stays mounted and fades instead of unmounting, so assert on the
    // opacity rather than on the finder.
    final opacity = tester.widget<AnimatedOpacity>(
      find.ancestor(
        of: find.byTooltip('Today'),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(opacity.opacity, 0);
  });

  testWidgets('the Today pill shows for another day of the current month', (
    tester,
  ) async {
    await withPhoneViewport(tester);
    await tester.pumpWidget(
      _wrap(
        appointments: Stream.value(const []),
        allUsers: Stream.value(const [_jane]),
        repo: repo,
      ),
    );
    await tester.pumpAndSettle();

    // Pick a different day that is still inside the visible month — the old
    // month-keyed rule left the pill hidden here.
    final today = DateTime.now();
    final other = today.day == 1
        ? DateTime(today.year, today.month, 2)
        : DateTime(today.year, today.month, today.day - 1);
    final key = ValueKey(
      'calendar-day-${other.year}-'
      '${other.month.toString().padLeft(2, '0')}-'
      '${other.day.toString().padLeft(2, '0')}',
    );
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();

    final opacity = tester.widget<AnimatedOpacity>(
      find.ancestor(
        of: find.byTooltip('Today'),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(opacity.opacity, 1);
  });

  testWidgets('tapping the header month opens the month and year picker', (
    tester,
  ) async {
    await withPhoneViewport(tester);
    await tester.pumpWidget(
      _wrap(
        appointments: Stream.value(const []),
        allUsers: Stream.value(const [_jane]),
        repo: repo,
      ),
    );
    await tester.pumpAndSettle();

    final today = DateTime.now();
    await tester.tap(find.text(DateFormat.MMMM().format(today)));
    await tester.pumpAndSettle();

    // Both wheels — every month and the whole year window, as before the
    // header block replaced the app bar.
    expect(find.byType(CupertinoPicker), findsNWidgets(2));
    expect(find.text(DateFormat.y().format(today)), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('agenda header pluralizes the selected day job count', (
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

    expect(find.text('1 JOB'), findsOneWidget);
    expect(find.textContaining('1 JOBS'), findsNothing);
  });

  testWidgets('the header block grows with text scale instead of clipping', (
    tester,
  ) async {
    await withPhoneViewport(tester);

    // The block sizes to its content now that it is a plain Column child, so
    // the property to pin is that it grows — the old PreferredSize had to
    // reserve height up front or the labels clipped.
    Future<double> headerHeight(double scale) async {
      await tester.pumpWidget(
        _wrap(
          appointments: Stream.value(const []),
          allUsers: Stream.value(const [_jane]),
          repo: repo,
          textScale: scale,
        ),
      );
      await tester.pumpAndSettle();
      return tester.getSize(find.byType(CalendarHeaderBlock)).height;
    }

    final atNormal = await headerHeight(1);
    final atDouble = await headerHeight(2);

    expect(atDouble, greaterThan(atNormal));
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolling the agenda collapses the grid into the week strip', (
    tester,
  ) async {
    await withPhoneViewport(tester);
    // Enough jobs that the single viewport actually scrolls.
    final today = DateTime.now();
    final many = [for (var i = 0; i < 14; i++) _appointment(i, today)];
    await tester.pumpWidget(
      _wrap(
        appointments: Stream.value(many),
        allUsers: Stream.value(const [_jane]),
        repo: repo,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CalendarMonthPager), findsOneWidget);
    expect(find.byType(CalendarWeekStrip), findsNothing);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();

    // Past 80px the grid unmounts and the strip rises inside the header.
    expect(find.byType(CalendarWeekStrip), findsOneWidget);
    expect(find.byType(CalendarMonthPager), findsNothing);
    expect(tester.takeException(), isNull);

    // Back to the top re-expands: the offset armed on the way up and fired
    // below 6px.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 600));
    await tester.pumpAndSettle();

    expect(find.byType(CalendarMonthPager), findsOneWidget);
    expect(find.byType(CalendarWeekStrip), findsNothing);
  });

  testWidgets('the split layout renders the agenda header in its own pane', (
    tester,
  ) async {
    // Tablet width, so _content takes the month | agenda branch.
    tester.view.physicalSize = const Size(1024 * 2, 768 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final today = DateTime.now();
    await tester.pumpWidget(
      _wrap(
        appointments: Stream.value([_appointment(1, today)]),
        allUsers: Stream.value(const [_jane]),
        repo: repo,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CalendarHeaderBlock), findsOneWidget);
    expect(find.text('1 JOB'), findsOneWidget);
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

    // Only the header pair's go-home pill now that the app bar is gone.
    expect(find.text('Calendar'), findsOneWidget);
    expect(find.byType(AppHeaderPair), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
