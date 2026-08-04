import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/connectivity/connectivity_providers.dart';
import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/employees_failure.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/features/employees/domain/models/new_account_credentials.dart';
import 'package:scheduling/features/employees/widgets/sheets/invite_person_sheet.dart';
import 'package:scheduling/l10n/l10n.dart';

class _MockRepo extends Mock implements EmployeesRepository {}

void main() {
  late _MockRepo repo;

  setUp(() {
    repo = _MockRepo();
    when(
      () => repo.createEmployeeAccount(
        name: any(named: 'name'),
        firstName: any(named: 'firstName'),
        lastName: any(named: 'lastName'),
        email: any(named: 'email'),
        phone: any(named: 'phone'),
        colorValue: any(named: 'colorValue'),
        jobTitle: any(named: 'jobTitle'),
        isAdmin: any(named: 'isAdmin'),
      ),
    ).thenAnswer(
      (_) async => const NewAccountCredentials(
        email: 'zoe@example.com',
        password: 'Welcome123!',
      ),
    );
  });

  /// Builds the whole lazy form at once so a below-the-fold row is findable.
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Widget wrap({Set<int> usedColors = const {}, double textScale = 1}) =>
      ProviderScope(
        overrides: [
          employeesRepositoryProvider.overrideWithValue(repo),
          isOfflineProvider.overrideWithValue(false),
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
            home: Scaffold(body: InvitePersonSheet(usedColors: usedColors)),
          ),
        ),
      );

  Future<void> fillRequired(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('firstName')), 'Theo');
    await tester.enterText(find.byKey(const Key('lastName')), 'Roy');
    await tester.enterText(find.byKey(const Key('email')), 'theo@x.com');
    await tester.pumpAndSettle();
  }

  testWidgets('sends every field to the callable', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await fillRequired(tester);
    await tester.tap(find.text('Technician'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('adminAccess')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Send Invite'));
    // Fixed-duration pump: the dialog's SelectableText cursor never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    verify(
      () => repo.createEmployeeAccount(
        name: 'Theo Roy',
        firstName: 'Theo',
        lastName: 'Roy',
        email: 'theo@x.com',
        phone: '',
        colorValue: any(named: 'colorValue'),
        jobTitle: 'technician',
        isAdmin: true,
      ),
    ).called(1);
  });

  testWidgets('admin access is off by default', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final adminSwitch = tester.widget<SwitchListTile>(
      find.byKey(const Key('adminAccess')),
    );
    expect(adminSwitch.value, isFalse);
  });

  testWidgets('shows the credentials dialog on success', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await fillRequired(tester);
    await tester.tap(find.text('Send Invite'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Both halves: the password alone loses which account it opens.
    expect(find.text('zoe@example.com'), findsOneWidget);
    expect(find.text('Welcome123!'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an email already in use becomes a field error, not a notice', (
    tester,
  ) async {
    when(
      () => repo.createEmployeeAccount(
        name: any(named: 'name'),
        firstName: any(named: 'firstName'),
        lastName: any(named: 'lastName'),
        email: any(named: 'email'),
        phone: any(named: 'phone'),
        colorValue: any(named: 'colorValue'),
        jobTitle: any(named: 'jobTitle'),
        isAdmin: any(named: 'isAdmin'),
      ),
    ).thenThrow(const EmployeesFailureEmailAlreadyExists());

    useTallViewport(tester);
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await fillRequired(tester);
    await tester.tap(find.text('Send Invite'));
    await tester.pumpAndSettle();

    expect(
      find.text('An employee with this email already exists'),
      findsOneWidget,
    );
    // The sheet stays open on a field error.
    expect(find.text('Send Invite'), findsOneWidget);
  });

  testWidgets('seeds a colour nobody already holds', (tester) async {
    useTallViewport(tester);
    // crewPalette[0] is taken, so the default pick must move on.
    await tester.pumpWidget(wrap(usedColors: const {0xFF005CC8}));
    await tester.pumpAndSettle();

    await fillRequired(tester);
    await tester.tap(find.text('Send Invite'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final captured = verify(
      () => repo.createEmployeeAccount(
        name: any(named: 'name'),
        firstName: any(named: 'firstName'),
        lastName: any(named: 'lastName'),
        email: any(named: 'email'),
        phone: any(named: 'phone'),
        colorValue: captureAny(named: 'colorValue'),
        jobTitle: any(named: 'jobTitle'),
        isAdmin: any(named: 'isAdmin'),
      ),
    ).captured.single;
    expect(captured, isNot('${0xFF005CC8}'));
  });

  testWidgets('renders the invited note', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    // Wording follows P4c: the admin hands over a starting password, there is
    // no signup code to "sign up with" any more.
    expect(
      find.textContaining('starting password'),
      findsOneWidget,
    );
  });

  testWidgets('survives 260x640 at 2.0 text scale', (tester) async {
    tester.view.physicalSize = const Size(260, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(textScale: 2));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
