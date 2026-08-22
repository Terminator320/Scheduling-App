import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/app/device_deregistration.dart';
import 'package:scheduling/core/images/appointment_image_loader.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/domain/clients_repository.dart';
import 'package:scheduling/features/live_activity/application/live_activity_registration_controller.dart';
import 'package:scheduling/features/notifications/application/push_registration_controller.dart';
import 'package:scheduling/features/presence/application/presence_sync_controller.dart';

class _MockPush extends Mock implements PushRegistrationController {}

class _MockPresence extends Mock implements PresenceSyncController {}

class _MockLiveActivity extends Mock
    implements LiveActivityRegistrationController {}

/// Records the photo-cache clear without reaching the file system.
///
/// Subclassed rather than mocked because the real loader's `clear` would
/// resolve the platform cache directory — a plugin call no widget test can
/// answer — and the property under test is only that it is CALLED, last.
class _RecordingLoader extends AppointmentImageLoader {
  _RecordingLoader(this.calls);

  final List<String> calls;

  @override
  Future<void> clear() async => calls.add('imageCache');
}

/// The real repositories resolve `FirebaseFirestore.instance` on construction,
/// which no widget test can answer — and only the clear is under test.
class _RecordingClients implements ClientsRepository {
  _RecordingClients(this.calls);

  final List<String> calls;

  @override
  void clearCaches() => calls.add('clients');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _RecordingAppointments implements AppointmentsRepository {
  _RecordingAppointments(this.calls);

  final List<String> calls;

  @override
  void clearCaches() => calls.add('appointments');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// `deregisterThisDevice` drops every server-side registration this device
/// holds, and it is reached from all three account exits (the runtime
/// account-deletion signal, Settings' sign-out, Settings' delete-account).
///
/// Two properties are pinned here because a regression in either is a PRIVACY
/// leak rather than a visible bug: a surviving `fcmToken` keeps pushing to a
/// signed-out device, and a surviving `presence/location` keeps rendering the
/// person on the admin's live map — where `LiveMapAggregator.join` filters on
/// missing/inactive user and never on freshness, so the stale pin looks live.
void main() {
  late _MockPush push;
  late _MockPresence presence;
  late _MockLiveActivity liveActivity;
  late List<String> calls;

  setUp(() {
    push = _MockPush();
    presence = _MockPresence();
    liveActivity = _MockLiveActivity();
    calls = [];

    when(push.unregisterCurrentDevice).thenAnswer((_) async {
      calls.add('push');
    });
    when(presence.unregister).thenAnswer((_) async {
      calls.add('presence');
    });
    when(liveActivity.unregister).thenAnswer((_) async {
      calls.add('liveActivity');
    });
  });

  /// Pumps a widget holding a real `WidgetRef` and runs the function through
  /// it — the signature is `WidgetRef`, not `Ref`, because all three exits are
  /// widget-layer.
  Future<void> run(WidgetTester tester) async {
    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pushRegistrationControllerProvider.overrideWithValue(push),
          presenceSyncControllerProvider.overrideWithValue(presence),
          liveActivityRegistrationControllerProvider.overrideWithValue(
            liveActivity,
          ),
          appointmentImageLoaderProvider.overrideWithValue(
            _RecordingLoader(calls),
          ),
          clientsRepositoryProvider.overrideWithValue(
            _RecordingClients(calls),
          ),
          appointmentsRepositoryProvider.overrideWithValue(
            _RecordingAppointments(calls),
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            captured = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await deregisterThisDevice(DeviceDeregistrationDeps.from(captured.read));
  }

  testWidgets(
    'tears down push, presence and Live Activity, then every local cache',
    (tester) async {
      // The ORDER is load-bearing: each server-side step needs the credential
      // that sign-out revokes, and callers run this ahead of the revocation.
      // The three local caches are purely local, so they go last — but they
      // must still GO: the photo bytes are on disk and outlive the process,
      // and both repository windows hold this user's client and appointment
      // PII for the life of the process.
      await run(tester);

      expect(calls, [
        'push',
        'presence',
        'liveActivity',
        'imageCache',
        'clients',
        'appointments',
      ]);
    },
  );

  testWidgets('a failing first step does not skip the other two', (
    tester,
  ) async {
    // The whole point. These used to be three bare awaits, so a throw from the
    // push teardown silently skipped presence and Live Activity — leaving
    // exactly the rows that are visible to OTHER people.
    when(push.unregisterCurrentDevice).thenThrow(Exception('no network'));

    await run(tester);

    expect(calls, [
      'presence',
      'liveActivity',
      'imageCache',
      'clients',
      'appointments',
    ]);
    verify(presence.unregister).called(1);
    verify(liveActivity.unregister).called(1);
  });

  testWidgets('a failing middle step does not skip the last', (tester) async {
    when(presence.unregister).thenThrow(Exception('permission denied'));

    await run(tester);

    expect(calls, [
      'push',
      'liveActivity',
      'imageCache',
      'clients',
      'appointments',
    ]);
  });

  testWidgets('never rethrows, so it cannot block the sign-out behind it', (
    tester,
  ) async {
    // Best-effort by contract: callers run this ahead of the action that
    // actually protects the user.
    when(push.unregisterCurrentDevice).thenThrow(Exception('a'));
    when(presence.unregister).thenThrow(Exception('b'));
    when(liveActivity.unregister).thenThrow(Exception('c'));

    await run(tester);

    expect(tester.takeException(), isNull);
  });
}
