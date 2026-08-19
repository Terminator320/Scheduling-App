import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/connectivity/connectivity_providers.dart';
import 'package:scheduling/core/notices/app_notice.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/employees_failure.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/employees/domain/models/job_title.dart';
import 'package:scheduling/features/employees/domain/models/new_account_credentials.dart';
import 'package:scheduling/features/employees/widgets/cards/pending_invite_tile.dart';
import 'package:scheduling/l10n/l10n.dart';

class _MockRepo extends Mock implements EmployeesRepository {}

const _invited = EmployeeRecord(
  id: 'inv1',
  name: 'Zoe Roy',
  firstName: 'Zoe',
  lastName: 'Roy',
  email: 'zoe@example.com',
  phone: '(514) 555-1234',
  status: 'invited',
  jobTitle: JobTitle.technician,
);

void main() {
  late _MockRepo repo;
  late NoticeService notices;
  late List<AppNotice> seen;

  setUp(() {
    repo = _MockRepo();
    notices = NoticeService();
    seen = [];
    notices.stream.listen(seen.add);
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
        password: 'Reset456!',
      ),
    );
    when(() => repo.deleteEmployeeAccount(any())).thenAnswer((_) async {});
  });

  tearDown(() => notices.dispose());

  /// The expanded body is tall; size the viewport instead of scrolling, since
  /// the tile has no scrollable of its own.
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Widget wrap(
    EmployeeRecord employee, {
    bool offline = false,
    double textScale = 1,
  }) => ProviderScope(
    overrides: [
      employeesRepositoryProvider.overrideWithValue(repo),
      isOfflineProvider.overrideWithValue(offline),
      noticeServiceProvider.overrideWithValue(notices),
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
        theme: lightTheme().copyWith(platform: TargetPlatform.android),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child ?? const SizedBox.shrink(),
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: PendingInviteTile(employee: employee),
          ),
        ),
      ),
    ),
  );

  /// The credentials render in SelectableTexts whose cursors never settle, so
  /// pump a fixed span rather than settling.
  Future<void> expand(WidgetTester tester) async {
    await tester.tap(find.text('Zoe Roy'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  void verifyNeverCreated() {
    verifyNever(
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
    );
  }

  testWidgets('collapsed row shows the person and the Invited chip only', (
    tester,
  ) async {
    useTallViewport(tester);
    await tester.pumpWidget(wrap(_invited));
    await tester.pumpAndSettle();

    expect(find.text('Zoe Roy'), findsOneWidget);
    expect(find.text('Invited'), findsOneWidget);
    expect(find.text('SIGN-IN DETAILS'), findsNothing);
    // The collapsed body must leave the tree entirely — a cross-fade would
    // keep the password findable, and readable by a screen reader, on a row
    // that looks closed.
    expect(find.text('Welcome123!'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'collapsed row falls back to first and last name when name is blank',
    (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(
        wrap(
          const EmployeeRecord(
            id: 'inv2',
            firstName: 'Amy',
            lastName: 'Adams',
            email: 'amy@example.com',
            status: 'invited',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Amy Adams'), findsOneWidget);
    },
  );

  testWidgets(
    'collapsed row does not repeat the email when it is already the display name',
    (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(
        wrap(
          const EmployeeRecord(
            id: 'inv3',
            email: 'amy@example.com',
            status: 'invited',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('amy@example.com'), findsOneWidget);
    },
  );

  testWidgets('expanding shows the credentials and calls nothing', (
    tester,
  ) async {
    useTallViewport(tester);
    await tester.pumpWidget(wrap(_invited));
    await tester.pumpAndSettle();

    await expand(tester);

    expect(find.text('SIGN-IN DETAILS'), findsOneWidget);
    // Twice on purpose: the collapsed header already identifies the person by
    // email, and the credentials block repeats it as the thing they sign in
    // with — copying the password without it loses which account it opens.
    expect(find.text('zoe@example.com'), findsNWidgets(2));
    expect(find.text('Welcome123!'), findsOneWidget);
    // The whole point of retiring the code flow: the starting password is a
    // fixed shared value, so opening a row costs no round-trip and rotates
    // nothing. The old flow re-minted a code on every expand.
    verifyNeverCreated();
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanding does not claim the password was just re-issued', (
    tester,
  ) async {
    useTallViewport(tester);
    await tester.pumpWidget(wrap(_invited));
    await tester.pumpAndSettle();

    await expand(tester);

    expect(find.textContaining('no longer works'), findsNothing);
  });

  testWidgets('Copy puts BOTH halves on the clipboard and relabels', (
    tester,
  ) async {
    useTallViewport(tester);
    final copied = <String?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String?);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(wrap(_invited));
    await tester.pumpAndSettle();
    await expand(tester);

    await tester.tap(find.text('Copy both'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Copying only the password loses which account it opens.
    expect(copied, ['zoe@example.com\nWelcome123!']);
    expect(find.text('Copied'), findsOneWidget);
    expect(find.text('Copy both'), findsNothing);
  });

  testWidgets('Reset password passes the stored record back whole', (
    tester,
  ) async {
    useTallViewport(tester);
    await tester.pumpWidget(wrap(_invited));
    await tester.pumpAndSettle();
    await expand(tester);

    await tester.tap(find.text('Reset password'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // No any() matchers on the wipeable fields: the server's re-provision
    // branch UPDATES each one with whatever it is handed, so a call site that
    // dropped one would silently blank it.
    verify(
      () => repo.createEmployeeAccount(
        name: 'Zoe Roy',
        firstName: 'Zoe',
        lastName: 'Roy',
        email: 'zoe@example.com',
        phone: '(514) 555-1234',
        // `_invited` picked no colour, so this is the record's default.
        colorValue: '${AppColors.crewDefault.toARGB32()}',
        jobTitle: 'technician',
        isAdmin: false,
      ),
    ).called(1);
  });

  testWidgets('Reset password shows the NEW password the server set', (
    tester,
  ) async {
    useTallViewport(tester);
    await tester.pumpWidget(wrap(_invited));
    await tester.pumpAndSettle();
    await expand(tester);

    await tester.tap(find.text('Reset password'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Echoed from the server, never assumed from the client constant.
    expect(find.text('Reset456!'), findsOneWidget);
    expect(find.text('Welcome123!'), findsNothing);
    expect(find.textContaining('no longer works'), findsOneWidget);
    expect(find.text('Password reset'), findsOneWidget);
  });

  testWidgets('Remove disables Reset password while deletion is in flight', (
    tester,
  ) async {
    useTallViewport(tester);
    final deleteCompleter = Completer<void>();
    when(
      () => repo.deleteEmployeeAccount('inv1'),
    ).thenAnswer((_) => deleteCompleter.future);

    await tester.pumpWidget(wrap(_invited));
    await tester.pumpAndSettle();
    await expand(tester);

    await tester.tap(find.text('Remove account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove account').last);
    await tester.pump();

    final resetButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Reset password'),
    );
    expect(resetButton.onPressed, isNull);

    deleteCompleter.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('Reset password disables Remove account while reset is in flight', (
    tester,
  ) async {
    useTallViewport(tester);
    final createCompleter = Completer<NewAccountCredentials>();
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
    ).thenAnswer((_) => createCompleter.future);

    await tester.pumpWidget(wrap(_invited));
    await tester.pumpAndSettle();
    await expand(tester);

    await tester.tap(find.text('Reset password'));
    await tester.pump();

    final removeButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Remove account'),
    );
    expect(removeButton.onPressed, isNull);

    createCompleter.complete(
      const NewAccountCredentials(
        email: 'zoe@example.com',
        password: 'Reset456!',
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('offline Reset notices instead of hanging on the call', (
    tester,
  ) async {
    useTallViewport(tester);
    await tester.pumpWidget(wrap(_invited, offline: true));
    await tester.pumpAndSettle();
    await expand(tester);

    await tester.tap(find.text('Reset password'));
    await tester.pump();

    expect(seen.single.message, contains('offline'));
    verifyNeverCreated();
  });

  testWidgets('Remove asks first and does nothing when cancelled', (
    tester,
  ) async {
    useTallViewport(tester);
    await tester.pumpWidget(wrap(_invited));
    await tester.pumpAndSettle();
    await expand(tester);

    await tester.tap(find.text('Remove account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    verifyNever(() => repo.deleteEmployeeAccount(any()));
  });

  testWidgets('Remove calls the repository on confirm and says nothing', (
    tester,
  ) async {
    useTallViewport(tester);
    await tester.pumpWidget(wrap(_invited));
    await tester.pumpAndSettle();
    await expand(tester);

    await tester.tap(find.text('Remove account'));
    await tester.pumpAndSettle();
    // The confirm button carries the same label as the row action.
    await tester.tap(find.text('Remove account').last);
    await tester.pumpAndSettle();

    verify(() => repo.deleteEmployeeAccount('inv1')).called(1);
    // No notice: the live stream drops the row, and that IS the confirmation.
    expect(seen, isEmpty);
  });

  testWidgets('a no-longer-pending refusal surfaces its own message', (
    tester,
  ) async {
    useTallViewport(tester);
    when(() => repo.deleteEmployeeAccount(any())).thenThrow(
      const EmployeesFailureAccountNoLongerPending(),
    );

    await tester.pumpWidget(wrap(_invited));
    await tester.pumpAndSettle();
    await expand(tester);

    await tester.tap(find.text('Remove account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove account').last);
    await tester.pumpAndSettle();

    expect(seen.single.message, contains('no longer pending'));
  });

  testWidgets('the expanded row holds a narrow viewport at 2.0 text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(260, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(_invited, textScale: 2));
    await tester.pumpAndSettle();
    await expand(tester);

    expect(find.text('Welcome123!'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
