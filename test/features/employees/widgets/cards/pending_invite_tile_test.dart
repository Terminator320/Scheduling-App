import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/connectivity/connectivity_providers.dart';
import 'package:scheduling/core/notices/app_notice.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/employees_failure.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/employees/domain/models/job_title.dart';
import 'package:scheduling/features/employees/widgets/cards/pending_invite_tile.dart';
import 'package:scheduling/l10n/l10n.dart';

class _MockRepo extends Mock implements EmployeesRepository {}

final _invited = EmployeeRecord(
  id: 'inv1',
  name: 'Zoé Roy',
  firstName: 'Zoé',
  lastName: 'Roy',
  email: 'zoe@example.com',
  phone: '(514) 555-1234',
  status: 'invited',
  jobTitle: JobTitle.technician,
  codeExpiresAt: DateTime(2026, 8, 16),
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
      () => repo.createEmployeeInvite(
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
    when(() => repo.revokeInvite(any())).thenAnswer((_) async {});
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

  /// The revealed code renders in a SelectableText whose cursor never settles,
  /// so pump a fixed span rather than settling.
  Future<void> expand(WidgetTester tester) async {
    await tester.tap(find.text('Zoé Roy'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('collapsed row shows the person and the Invited chip only', (
    tester,
  ) async {
    useTallViewport(tester);
    await tester.pumpWidget(wrap(_invited));
    await tester.pumpAndSettle();

    expect(find.text('Zoé Roy'), findsOneWidget);
    expect(find.text('Invited'), findsOneWidget);
    expect(find.text('INVITE CODE'), findsNothing);
    expect(find.text('K7Q2-9MZ4-XR8T'), findsNothing);
    verifyNever(
      () => repo.createEmployeeInvite(
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
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanding reveals the freshly issued code', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(wrap(_invited));
    await tester.pumpAndSettle();

    await expand(tester);

    expect(find.text('INVITE CODE'), findsOneWidget);
    expect(find.text('K7Q2-9MZ4-XR8T'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the re-issue passes the stored record back, so a re-issue cannot wipe '
    'the invited person phone or job title',
    (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(wrap(_invited));
      await tester.pumpAndSettle();

      await expand(tester);

      verify(
        () => repo.createEmployeeInvite(
          name: 'Zoé Roy',
          firstName: 'Zoé',
          lastName: 'Roy',
          email: 'zoe@example.com',
          phone: '(514) 555-1234',
          colorValue: '4280391411',
          jobTitle: 'technician',
          isAdmin: false,
        ),
      ).called(1);
    },
  );

  testWidgets(
    'expand -> collapse -> expand issues exactly one code (the cached code '
    'survives, so re-opening the row burns no rate-limit slot)',
    (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(wrap(_invited));
      await tester.pumpAndSettle();

      await expand(tester);
      // Collapse.
      await tester.tap(find.text('Zoé Roy'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('K7Q2-9MZ4-XR8T'), findsNothing);
      // Re-expand.
      await expand(tester);
      expect(find.text('K7Q2-9MZ4-XR8T'), findsOneWidget);

      verify(
        () => repo.createEmployeeInvite(
          name: any(named: 'name'),
          firstName: any(named: 'firstName'),
          lastName: any(named: 'lastName'),
          email: any(named: 'email'),
          phone: any(named: 'phone'),
          colorValue: any(named: 'colorValue'),
          jobTitle: any(named: 'jobTitle'),
          isAdmin: any(named: 'isAdmin'),
        ),
      ).called(1);
    },
  );

  testWidgets('Copy puts the code on the clipboard and relabels to Copied', (
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

    await tester.tap(find.text('Copy code'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(copied, ['K7Q2-9MZ4-XR8T']);
    expect(find.text('Copied'), findsOneWidget);
    expect(find.text('Copy code'), findsNothing);
  });

  testWidgets('the expiry caption renders the stamped date', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(wrap(_invited));
    await tester.pumpAndSettle();
    await expand(tester);

    expect(find.textContaining('New code · expires'), findsOneWidget);
  });

  testWidgets('the expiry caption is omitted when codeExpiresAt is null', (
    tester,
  ) async {
    useTallViewport(tester);
    await tester.pumpWidget(
      wrap(_invited.copyWith(codeExpiresAt: null)),
    );
    await tester.pumpAndSettle();
    await expand(tester);

    // The code is up, so the block is present — only the dated caption is gone.
    expect(find.text('K7Q2-9MZ4-XR8T'), findsOneWidget);
    expect(find.textContaining('expires'), findsNothing);
  });

  testWidgets('Resend issues another code and relabels the button', (
    tester,
  ) async {
    useTallViewport(tester);
    await tester.pumpWidget(wrap(_invited));
    await tester.pumpAndSettle();
    await expand(tester);

    when(
      () => repo.createEmployeeInvite(
        name: any(named: 'name'),
        firstName: any(named: 'firstName'),
        lastName: any(named: 'lastName'),
        email: any(named: 'email'),
        phone: any(named: 'phone'),
        colorValue: any(named: 'colorValue'),
        jobTitle: any(named: 'jobTitle'),
        isAdmin: any(named: 'isAdmin'),
      ),
    ).thenAnswer((_) async => 'AAAA-BBBB-CCCC');

    await tester.tap(find.text('Resend code'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('AAAA-BBBB-CCCC'), findsOneWidget);
    expect(find.text('New code ready'), findsOneWidget);
  });

  testWidgets('Revoke asks first and does nothing when cancelled', (
    tester,
  ) async {
    useTallViewport(tester);
    await tester.pumpWidget(wrap(_invited));
    await tester.pumpAndSettle();
    await expand(tester);

    await tester.tap(find.text('Revoke invite').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    verifyNever(() => repo.revokeInvite(any()));
  });

  testWidgets('Revoke calls the repository on confirm and says nothing', (
    tester,
  ) async {
    useTallViewport(tester);
    await tester.pumpWidget(wrap(_invited));
    await tester.pumpAndSettle();
    await expand(tester);

    await tester.tap(find.text('Revoke invite').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // The dialog's confirm carries the same label as the row button.
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Revoke invite'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    verify(() => repo.revokeInvite('inv1')).called(1);
    // The live stream dropping the row IS the confirmation.
    expect(seen, isEmpty);
  });

  testWidgets('a no-longer-pending refusal surfaces its own message', (
    tester,
  ) async {
    useTallViewport(tester);
    when(
      () => repo.revokeInvite(any()),
    ).thenThrow(const EmployeesFailureInviteNoLongerPending());

    await tester.pumpWidget(wrap(_invited));
    await tester.pumpAndSettle();
    await expand(tester);

    await tester.tap(find.text('Revoke invite').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Revoke invite'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(seen, hasLength(1));
    expect(seen.single.message, contains('no longer pending'));
  });

  testWidgets('offline expansion notices instead of hanging on the call', (
    tester,
  ) async {
    useTallViewport(tester);
    await tester.pumpWidget(wrap(_invited, offline: true));
    await tester.pumpAndSettle();
    await expand(tester);

    verifyNever(
      () => repo.createEmployeeInvite(
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
    expect(seen, hasLength(1));
    expect(seen.single.message, contains('offline'));
    // The retry affordance is what the admin is left with.
    expect(find.text('Show code'), findsOneWidget);
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

    expect(find.text('K7Q2-9MZ4-XR8T'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
