import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/connectivity/connectivity_providers.dart';
import 'package:scheduling/core/notices/app_notice.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/auth/domain/auth_failure.dart';
import 'package:scheduling/features/auth/services/account_deletion_service.dart';
import 'package:scheduling/features/settings/widgets/views/delete_account_flow.dart';
import 'package:scheduling/l10n/l10n.dart';

class _MockDeletionService extends Mock implements AccountDeletionService {}

/// The smallest host the mixin needs — Settings itself carries app-lock
/// lifecycle and the notification toggles, none of which this exercises.
class _Host extends ConsumerStatefulWidget {
  const _Host({required this.service});

  final AccountDeletionService service;

  @override
  ConsumerState<_Host> createState() => _HostState();
}

class _HostState extends ConsumerState<_Host> with DeleteAccountFlow<_Host> {
  @override
  AccountDeletionService get deletionService => widget.service;

  @override
  bool get isAdminAccount => false;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: confirmDeleteAccount,
        child: const Text('delete'),
      ),
    ),
  );
}

void main() {
  /// Drives the flow to the re-auth step and returns the notice it pushed.
  Future<String> noticeFor(WidgetTester tester, AuthFailure failure) async {
    final service = _MockDeletionService();
    when(
      () => service.reauthenticateWithPassword(any()),
    ).thenAnswer((_) async => throw failure);

    final container = ProviderContainer(
      overrides: [isOfflineProvider.overrideWithValue(false)],
    );
    addTearDown(container.dispose);
    final notices = <AppNotice>[];
    final sub = container
        .read(noticeServiceProvider)
        .stream
        .listen(notices.add);
    addTearDown(sub.cancel);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: lightTheme(),
          home: _Host(service: service),
        ),
      ),
    );

    await tester.tap(find.text('delete'));
    await tester.pumpAndSettle();

    // The confirm dialog, then the re-auth prompt — both label their primary
    // action "Delete permanently", so they are dismissed in order.
    await tester.tap(find.widgetWithText(FilledButton, 'Delete permanently'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'hunter2');
    await tester.tap(find.widgetWithText(FilledButton, 'Delete permanently'));
    await tester.pumpAndSettle();

    expect(notices, hasLength(1));
    return notices.single.message;
  }

  setUpAll(() {
    registerFallbackValue('');
  });

  testWidgets(
    'a missing account during re-auth asks the user to log in again',
    (
      tester,
    ) async {
      // The whole point of the reauthentication context: without it this reads
      // "No account found with this email", naming an address the person never
      // typed on a screen that only asked for their password.
      expect(
        await noticeFor(tester, const AuthFailureUserNotFound()),
        'Please log in again and retry',
      );
    },
  );

  testWidgets('a wrong password during re-auth asks the user to log in again', (
    tester,
  ) async {
    expect(
      await noticeFor(tester, const AuthFailureWrongCredentials()),
      'Please log in again and retry',
    );
  });
}
