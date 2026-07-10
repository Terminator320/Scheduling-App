import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/employees/screens/employees_screen.dart';
import 'package:scheduling/l10n/l10n.dart';

class _MockEmployeesRepo extends Mock implements EmployeesRepository {}

const _jane = EmployeeRecord(
  id: 'e1',
  name: 'Jane Doe',
  email: 'jane@example.com',
  status: 'active',
);

const _bob = EmployeeRecord(
  id: 'e2',
  name: 'Bob Smith',
  email: 'bob@example.com',
  status: 'active',
);

const _disabledJane = EmployeeRecord(
  id: 'e1',
  name: 'Jane Doe',
  email: 'jane@example.com',
  status: 'disabled',
);

const _activeJane = EmployeeRecord(
  id: 'e1',
  name: 'Jane Doe',
  email: 'jane@example.com',
  status: 'active',
);

Widget _wrap({
  required Stream<List<EmployeeRecord>> Function() employees,
  List<Override> overrides = const [],
}) {
  // The admin list now reads from allUsersStreamProvider (so disabled and
  // invited users stay reachable for re-enable); the screen still watches
  // employeesStreamProvider for loading/error state. Override both. Each
  // call to employees() must return a fresh single-subscription stream
  // because the two providers subscribe independently.
  return ProviderScope(
    overrides: [
      employeesStreamProvider.overrideWith((_) => employees()),
      allUsersStreamProvider.overrideWith((_) => employees()),
      ...overrides,
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
        home: const AddEmployeePage(isAdmin: true, employeeId: 'admin'),
      ),
    ),
  );
}

/// A broadcast users stream plus an `emit` to push new snapshots. Each `make`
/// call replays the latest value on subscription (a bare broadcast stream would
/// drop the seed for a late subscriber) then forwards live updates — so the two
/// independently-subscribing providers both see the seed and every update.
typedef _SeededUsers = ({
  Stream<List<EmployeeRecord>> Function() make,
  void Function(List<EmployeeRecord>) emit,
  StreamController<List<EmployeeRecord>> controller,
});

_SeededUsers _seededUsers(List<EmployeeRecord> initial) {
  final controller = StreamController<List<EmployeeRecord>>.broadcast();
  var current = initial;
  Stream<List<EmployeeRecord>> make() async* {
    yield current;
    yield* controller.stream;
  }

  void emit(List<EmployeeRecord> next) {
    current = next;
    controller.add(next);
  }

  return (make: make, emit: emit, controller: controller);
}

/// Forces the wide viewport the master-detail split needs to render its detail
/// pane (>= Breakpoints.tablet), resetting after the test.
void _useWideViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('renders employee cards from the stream', (tester) async {
    await tester.pumpWidget(
      _wrap(employees: () => Stream.value(const [_jane, _bob])),
    );
    await tester.pumpAndSettle();

    expect(find.text('Jane Doe'), findsOneWidget);
    expect(find.text('Bob Smith'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows empty-state copy when the list is empty', (tester) async {
    await tester.pumpWidget(_wrap(employees: () => Stream.value(const [])));
    await tester.pumpAndSettle();

    expect(find.textContaining('No employees'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows error copy when the stream errors', (tester) async {
    await tester.pumpWidget(
      _wrap(employees: () => Stream.error(StateError('boom'))),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('rror'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'split-layout detail pane reflects an external re-enable of the selected '
    'employee instead of showing the stale disabled snapshot',
    (tester) async {
      _useWideViewport(tester);
      final users = _seededUsers(const [_disabledJane]);
      addTearDown(users.controller.close);

      await tester.pumpWidget(_wrap(employees: users.make));
      await tester.pumpAndSettle();

      // Open the disabled employee in the split-layout detail pane.
      await tester.tap(find.text('Jane Doe'));
      await tester.pumpAndSettle();
      expect(find.text('Enable employee'), findsOneWidget);

      // Another admin re-enables her elsewhere; the live stream emits active.
      users.emit(const [_activeJane]);
      await tester.pumpAndSettle();

      expect(find.text('Disable employee'), findsOneWidget);
      expect(find.text('Enable employee'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'split-layout detail pane clears when the selected employee vanishes '
    'from the live stream (deleted elsewhere), leaving no ghost actions',
    (tester) async {
      _useWideViewport(tester);
      final users = _seededUsers(const [_disabledJane]);
      addTearDown(users.controller.close);

      await tester.pumpWidget(_wrap(employees: users.make));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Jane Doe'));
      await tester.pumpAndSettle();
      expect(find.text('Enable employee'), findsOneWidget);

      // The employee is deleted (e.g. by another admin) — the live list drops
      // them entirely.
      users.emit(const []);
      await tester.pumpAndSettle();

      // No ghost detail pane with live Enable/Disable/Delete actions.
      expect(find.text('Enable employee'), findsNothing);
      expect(find.text('Disable employee'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tapping Enable in the split-layout detail pane flips the employee to '
    'active (the reported re-enable flow)',
    (tester) async {
      _useWideViewport(tester);
      final users = _seededUsers(const [_disabledJane]);
      addTearDown(users.controller.close);

      final repo = _MockEmployeesRepo();
      // Re-enabling writes status active; mirror that onto the live stream the
      // way Firestore's listener would, so the detail pane can reconcile.
      when(
        () => repo.reactivateEmployee('e1'),
      ).thenAnswer((_) async => users.emit(const [_activeJane]));

      await tester.pumpWidget(
        _wrap(
          employees: users.make,
          overrides: [employeesRepositoryProvider.overrideWithValue(repo)],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Jane Doe'));
      await tester.pumpAndSettle();

      // Tap the pane's Enable button, then confirm in the dialog (both carry
      // the "Enable employee" label, so scope the second tap to the dialog).
      await tester.tap(find.widgetWithText(FilledButton, 'Enable employee'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Enable employee'),
        ),
      );
      await tester.pumpAndSettle();

      verify(() => repo.reactivateEmployee('e1')).called(1);
      expect(find.text('Disable employee'), findsOneWidget);
      expect(find.text('Enable employee'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
