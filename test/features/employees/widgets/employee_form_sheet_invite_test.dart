import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/features/employees/widgets/sheets/employee_form_sheet.dart';
import 'package:scheduling/l10n/l10n.dart';

class _MockRepo extends Mock implements EmployeesRepository {}

Widget _wrap(Widget child, {required EmployeesRepository repo}) {
  return ProviderScope(
    overrides: [
      employeesRepositoryProvider.overrideWithValue(repo),
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
        home: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  late _MockRepo mockRepo;

  setUp(() {
    mockRepo = _MockRepo();
    when(
      () => mockRepo.createEmployeeInvite(
        name: any(named: 'name'),
        firstName: any(named: 'firstName'),
        lastName: any(named: 'lastName'),
        email: any(named: 'email'),
        phone: any(named: 'phone'),
        colorValue: any(named: 'colorValue'),
        jobTitle: any(named: 'jobTitle'),
        isAdmin: any(named: 'isAdmin'),
      ),
    ).thenAnswer((_) async => 'K7Q2-9MZ4-XR8T');
  });

  testWidgets(
    'invite branch: createEmployeeInvite is called and signup-code dialog shows the code',
    (tester) async {
      await tester.pumpWidget(
        _wrap(const EmployeeFormSheet(), repo: mockRepo),
      );
      await tester.pumpAndSettle();

      // Fill in name (required) — first text field.
      await tester.enterText(find.byType(TextField).at(0), 'Alice');
      // Fill in email (required) — second text field.
      await tester.enterText(find.byType(TextField).at(1), 'alice@example.com');
      await tester.pumpAndSettle();

      // Tap the submit button ("Send Invite").
      final sendInviteButton = find.text('Send Invite');
      await tester.ensureVisible(sendInviteButton);
      await tester.tap(sendInviteButton);
      // Fixed-duration pump instead of pumpAndSettle: the dialog's SelectableText
      // cursor animation never settles.
      await tester.pump(); // process tap + start async operation
      await tester.pump(
        const Duration(milliseconds: 300),
      ); // resolve mock future + animate dialog in

      // The signup-code dialog should be visible with the returned code.
      expect(find.text('K7Q2-9MZ4-XR8T'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
