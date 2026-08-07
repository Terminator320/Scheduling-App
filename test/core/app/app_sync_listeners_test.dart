import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/app/app_sync_listeners.dart';
import 'package:scheduling/core/connectivity/connectivity_providers.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/calendar/data/appointment_image_upload_service.dart';
import 'package:scheduling/features/live_activity/application/live_activity_registration_controller.dart';
import 'package:scheduling/features/notifications/application/push_registration_controller.dart';
import 'package:scheduling/features/presence/application/presence_sync_controller.dart';

class _FakePush extends Mock implements PushRegistrationController {}

class _FakePresence extends Mock implements PresenceSyncController {}

class _FakeLiveActivity extends Mock
    implements LiveActivityRegistrationController {}

class _FakeUploads extends Mock implements AppointmentImageUploadService {}

/// Drives `isOfflineProvider` from the test so the offline→online flip can be
/// replayed as a real transition (a plain Provider can't change value).
class _OfflineController extends Notifier<bool> {
  @override
  bool build() => false;

  void goOffline() => state = true;

  void goOnline() => state = false;
}

final _offline = NotifierProvider<_OfflineController, bool>(
  _OfflineController.new,
);

const _account = {'id': 'u1', 'role': 'employee', 'status': 'active'};

void main() {
  late _FakePush push;
  late _FakePresence presence;
  late _FakeLiveActivity liveActivity;
  late _FakeUploads uploads;
  late StreamController<Map<String, dynamic>> accountDocs;

  setUp(() {
    push = _FakePush();
    presence = _FakePresence();
    liveActivity = _FakeLiveActivity();
    uploads = _FakeUploads();
    accountDocs = StreamController<Map<String, dynamic>>.broadcast();
    when(() => push.sync()).thenAnswer((_) async {});
    when(() => presence.sync()).thenAnswer((_) async {});
    when(() => liveActivity.sync()).thenAnswer((_) async {});
    when(() => uploads.drainPending()).thenAnswer((_) async {});
  });

  tearDown(() => accountDocs.close());

  /// Mounts a bare ConsumerWidget that registers the listeners, so the wiring
  /// gets exercised without needing a full MaterialApp. That's exactly why
  /// AppSyncListeners was pulled out of `_PaulAppState` in the first place.
  Future<ProviderContainer> pump(WidgetTester tester) async {
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserDocProvider.overrideWith((ref) => accountDocs.stream),
          isOfflineProvider.overrideWith((ref) => ref.watch(_offline)),
          pushRegistrationControllerProvider.overrideWithValue(push),
          presenceSyncControllerProvider.overrideWithValue(presence),
          liveActivityRegistrationControllerProvider.overrideWithValue(
            liveActivity,
          ),
          appointmentImageUploadProvider.overrideWithValue(uploads),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            AppSyncListeners(ref).registerAll();
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  group('device registration', () {
    testWidgets('every account-doc emission re-syncs all three controllers', (
      tester,
    ) async {
      await pump(tester);

      accountDocs.add(_account);
      await tester.pump();

      verify(() => push.sync()).called(1);
      verify(() => presence.sync()).called(1);
      verify(() => liveActivity.sync()).called(1);
    });

    testWidgets('a later emission syncs again (token/locale can change)', (
      tester,
    ) async {
      await pump(tester);

      accountDocs.add(_account);
      await tester.pump();
      accountDocs.add({..._account, 'name': 'renamed'});
      await tester.pump();

      verify(() => push.sync()).called(2);
    });
  });

  group('offline→online photo drain', () {
    testWidgets('drains on the offline→online flip while signed in', (
      tester,
    ) async {
      final container = await pump(tester);
      accountDocs.add(_account);
      await tester.pump();
      clearInteractions(uploads);

      container.read(_offline.notifier).goOffline();
      await tester.pump();
      container.read(_offline.notifier).goOnline();
      await tester.pump();

      verify(() => uploads.drainPending()).called(1);
    });

    testWidgets('does NOT drain when signed out', (tester) async {
      // Storage rules need an authed user, so a signed-out drain would just
      // re-queue the batch. That's why the listener gates on a populated account doc.
      final container = await pump(tester);

      container.read(_offline.notifier).goOffline();
      await tester.pump();
      container.read(_offline.notifier).goOnline();
      await tester.pump();

      verifyNever(() => uploads.drainPending());
    });

    testWidgets('does NOT drain on the online→offline direction', (
      tester,
    ) async {
      final container = await pump(tester);
      accountDocs.add(_account);
      await tester.pump();
      clearInteractions(uploads);

      container.read(_offline.notifier).goOffline();
      await tester.pump();

      verifyNever(() => uploads.drainPending());
    });
  });

  group('first-account-doc drain', () {
    testWidgets('drains once when the account doc first arrives', (
      tester,
    ) async {
      await pump(tester);

      accountDocs.add(_account);
      await tester.pump();

      verify(() => uploads.drainPending()).called(1);
    });

    testWidgets('does not re-drain on subsequent populated emissions', (
      tester,
    ) async {
      await pump(tester);

      accountDocs.add(_account);
      await tester.pump();
      accountDocs.add({..._account, 'name': 'renamed'});
      await tester.pump();

      // The transition is empty→populated, not "any populated emission".
      verify(() => uploads.drainPending()).called(1);
    });

    testWidgets('an empty doc (signed out) does not drain', (tester) async {
      await pump(tester);

      accountDocs.add(const {});
      await tester.pump();

      verifyNever(() => uploads.drainPending());
    });
  });
}
