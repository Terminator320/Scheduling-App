// test/employee_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/employees/widgets/employee_card.dart';
import 'package:scheduling/l10n/app_localizations.dart';
import 'package:scheduling/shared/widgets/app_avatar.dart';
import 'package:scheduling/shared/widgets/status_chip.dart';

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

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
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

  testWidgets('shows StatusChip', (tester) async {
    await tester.pumpWidget(
      _wrap(EmployeeCard(employee: _fakeEmployee(), onTap: () {})),
    );
    expect(find.byType(StatusChip), findsOneWidget);
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

  testWidgets('does not overflow at small screen + 2x text', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(260 * 3, 200 * 3);
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
