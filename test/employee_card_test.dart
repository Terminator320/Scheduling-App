// test/employee_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/employees/application/employee_schedule_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/employees/domain/models/job_title.dart';
import 'package:scheduling/features/employees/widgets/cards/employee_card.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/user_status_chip.dart';
import 'package:scheduling/shared/widgets/primitives/app_avatar.dart';

EmployeeRecord _fakeEmployee({
  String status = 'active',
  bool isAdmin = false,
}) => EmployeeRecord(
  id: 'e1',
  name: 'Alex Vogas',
  email: 'alex@salon.com',
  phone: '514-555-0100',
  role: isAdmin ? 'admin' : 'employee',
  status: status,
  uid: 'uid1',
  color: const Color(0xFF6366F1),
);

Widget _wrap(Widget child, {Map<String, int> jobsToday = const {}}) =>
    ProviderScope(
      overrides: [employeeJobsTodayProvider.overrideWithValue(jobsToday)],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

void main() {
  testWidgets('shows employee name', (tester) async {
    await tester.pumpWidget(
      _wrap(EmployeeCard(employee: _fakeEmployee(), onTap: () {})),
    );
    expect(find.text('Alex Vogas'), findsOneWidget);
  });

  testWidgets('shows employee email', (tester) async {
    await tester.pumpWidget(
      _wrap(EmployeeCard(employee: _fakeEmployee(), onTap: () {})),
    );
    expect(find.text('alex@salon.com'), findsOneWidget);
  });

  testWidgets('shows AppAvatar', (tester) async {
    await tester.pumpWidget(
      _wrap(EmployeeCard(employee: _fakeEmployee(), onTap: () {})),
    );
    expect(find.byType(AppAvatar), findsOneWidget);
  });

  testWidgets('shows UserStatusChip', (tester) async {
    await tester.pumpWidget(
      _wrap(EmployeeCard(employee: _fakeEmployee(), onTap: () {})),
    );
    expect(find.byType(UserStatusChip), findsOneWidget);
  });

  testWidgets('calls onTap when tapped', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _wrap(
        EmployeeCard(employee: _fakeEmployee(), onTap: () => tapped = true),
      ),
    );
    await tester.tap(find.byType(EmployeeCard));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('does not show Edit or Delete IconButtons', (tester) async {
    await tester.pumpWidget(
      _wrap(EmployeeCard(employee: _fakeEmployee(), onTap: () {})),
    );
    final iconButtons = tester.widgetList<IconButton>(find.byType(IconButton));
    expect(iconButtons, isEmpty);
  });

  testWidgets('disabled employee has reduced opacity', (tester) async {
    await tester.pumpWidget(
      _wrap(
        EmployeeCard(
          employee: _fakeEmployee(status: 'disabled'),
          onTap: () {},
        ),
      ),
    );
    expect(find.byType(Opacity), findsOneWidget);
    final opacity = tester.widget<Opacity>(find.byType(Opacity));
    expect(opacity.opacity, closeTo(0.65, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows job title and today count', (tester) async {
    await tester.pumpWidget(
      _wrap(
        EmployeeCard(
          employee: const EmployeeRecord(
            id: 'e1',
            name: 'Theo Roy',
            email: 'theo@x.com',
            jobTitle: JobTitle.leadTech,
          ),
          onTap: () {},
        ),
        jobsToday: const {'e1': 3},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lead tech · 3 jobs today'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('falls back to the email with no title and no jobs', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        EmployeeCard(
          employee: const EmployeeRecord(
            id: 'e1',
            name: 'Theo Roy',
            email: 'theo@x.com',
          ),
          onTap: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('theo@x.com'), findsOneWidget);
  });

  testWidgets('does not overflow at small screen + 2x text', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: _wrap(EmployeeCard(employee: _fakeEmployee(), onTap: () {})),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
