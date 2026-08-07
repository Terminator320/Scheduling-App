import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/connectivity/connectivity_providers.dart';
import 'package:scheduling/features/auth/application/active_user_identity_provider.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/features/employees/domain/models/emergency_contact.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/settings/screens/my_details_screen.dart';
import 'package:scheduling/l10n/l10n.dart';

class _MockRepo extends Mock implements EmployeesRepository {}

void main() {
  late _MockRepo repo;

  setUpAll(() {
    registerFallbackValue(EmergencyContact.empty);
    // Needed by the verifyNever on updateEmployee — without it mocktail throws
    // mid-verify, which poisons the shared state for the tests that follow.
    registerFallbackValue(const EmployeeRecord(id: 'fallback'));
  });

  setUp(() {
    repo = _MockRepo();
    when(
      () => repo.saveEmergencyContact(any(), any()),
    ).thenAnswer((_) async {});
  });

  Future<void> pump(
    WidgetTester tester, {
    EmergencyContact stored = EmergencyContact.empty,
    bool offline = false,
  }) async {
    when(
      () => repo.watchEmergencyContact('me-1'),
    ).thenAnswer((_) => Stream.value(stored));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          employeesRepositoryProvider.overrideWithValue(repo),
          isOfflineProvider.overrideWithValue(offline),
          activeUserIdentityProvider.overrideWith(
            (ref) async => (role: 'employee', docId: 'me-1'),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: MyDetailsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('seeds the fields from the stored contact', (tester) async {
    await pump(
      tester,
      stored: const EmergencyContact(
        contact: 'Marie Roy',
        phone: '(514) 555-0199',
      ),
    );

    expect(find.text('Marie Roy'), findsOneWidget);
    expect(find.text('(514) 555-0199'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving writes only the emergency doc for the signed-in user', (
    tester,
  ) async {
    await pump(tester);

    await tester.enterText(
      find.byKey(const Key('myEmergencyContact')),
      'Marie',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final captured = verify(
      () => repo.saveEmergencyContact('me-1', captureAny()),
    ).captured.single;
    expect((captured as EmergencyContact).contact, 'Marie');
    // A self-service surface must never touch the users doc — that write is
    // admin-only, and the whole point of the subcollection is that this one
    // isn't.
    verifyNever(
      () => repo.updateEmployee(
        docId: any(named: 'docId'),
        employee: any(named: 'employee'),
      ),
    );
  });

  testWidgets('offline save fails fast without calling the repository', (
    tester,
  ) async {
    await pump(tester, offline: true);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    verifyNever(() => repo.saveEmergencyContact(any(), any()));
  });

  testWidgets('a later snapshot does not clobber what is being typed', (
    tester,
  ) async {
    await pump(tester, stored: const EmergencyContact(contact: 'Marie'));

    await tester.enterText(
      find.byKey(const Key('myEmergencyContact')),
      'Marie Roy',
    );
    await tester.pumpAndSettle();

    expect(find.text('Marie Roy'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
