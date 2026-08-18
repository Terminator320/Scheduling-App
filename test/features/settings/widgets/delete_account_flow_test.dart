import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/connectivity/connectivity_providers.dart';
import 'package:scheduling/core/images/appointment_image_loader.dart';
import 'package:scheduling/core/notices/app_notice.dart';
import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/auth/domain/auth_failure.dart';
import 'package:scheduling/features/auth/services/account_deletion_service.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/features/live_activity/application/live_activity_registration_controller.dart';
import 'package:scheduling/features/notifications/application/push_registration_controller.dart';
import 'package:scheduling/features/presence/application/presence_sync_controller.dart';
import 'package:scheduling/features/settings/widgets/views/delete_account_flow.dart';
import 'package:scheduling/l10n/l10n.dart';

class _MockDeletionService extends Mock implements AccountDeletionService {}
class _MockAuthService extends Mock implements AuthService {}
class _MockPush extends Mock implements PushRegistrationController {}
class _MockPresence extends Mock implements PresenceSyncController {}
class _MockLiveActivity extends Mock
    implements LiveActivityRegistrationController {}

class _RecordingLoader extends AppointmentImageLoader {
  _RecordingLoader();

  @override
  Future<void> clear() async {}
}

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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: signOut,
            child: const Text('sign out'),
          ),
          TextButton(
            onPressed: confirmDeleteAccount,
            child: const Text('delete'),
          ),
        ],
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

  testWidgets('double-tapping delete opens only one confirm flow', (
    tester,
  ) async {
    final service = _MockDeletionService();
    when(
      () => service.reauthenticateWithPassword(any()),
    ).thenAnswer((_) async => throw const AuthFailureWrongCredentials());

    final container = ProviderContainer(
      overrides: [isOfflineProvider.overrideWithValue(false)],
    );
    addTearDown(container.dispose);

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
    await tester.tap(find.text('delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete account?'), findsOneWidget);
  });

  testWidgets('delete flow cannot start while sign-out is already in progress', (
    tester,
  ) async {
    final service = _MockDeletionService();
    final auth = _MockAuthService();
    final push = _MockPush();
    final presence = _MockPresence();
    final liveActivity = _MockLiveActivity();
    final signOutCompleter = Completer<void>();
    Future<void> waitForSignOut(_) => signOutCompleter.future;

    when(auth.signOut).thenAnswer(waitForSignOut);
    when(push.unregisterCurrentDevice).thenAnswer((_) async {});
    when(presence.unregister).thenAnswer((_) async {});
    when(liveActivity.unregister).thenAnswer((_) async {});

    final container = ProviderContainer(
      overrides: [
        isOfflineProvider.overrideWithValue(false),
        authServiceProvider.overrideWithValue(auth),
        pushRegistrationControllerProvider.overrideWithValue(push),
        presenceSyncControllerProvider.overrideWithValue(presence),
        liveActivityRegistrationControllerProvider.overrideWithValue(
          liveActivity,
        ),
        appointmentImageLoaderProvider.overrideWithValue(_RecordingLoader()),
      ],
    );
    addTearDown(container.dispose);

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

    await tester.tap(find.text('sign out'));
    await tester.pump();

    await tester.tap(find.text('delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete account?'), findsNothing);
    verifyNever(() => service.reauthenticateWithPassword(any()));

    signOutCompleter.complete();
  });
}
