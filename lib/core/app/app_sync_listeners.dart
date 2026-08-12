import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/connectivity/connectivity_providers.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/calendar/data/appointment_image_upload_service.dart';
import 'package:scheduling/features/home_widget/application/widget_sync_service.dart';
import 'package:scheduling/features/live_activity/application/live_activity_registration_controller.dart';
import 'package:scheduling/features/notifications/application/push_registration_controller.dart';
import 'package:scheduling/features/presence/application/presence_sync_controller.dart';
import 'package:scheduling/features/siri/application/schedule_snapshot_provider.dart';
import 'package:scheduling/features/siri/application/schedule_snapshot_service.dart';

/// Cross-cutting sync wiring — device registration, mirrors, photo drain — pulled out here for testability. Account-lifecycle listeners stay in main.dart, since registration order matters there.
///
/// [registerAll] must be called from `build`, like any `ref.listen`.
class AppSyncListeners {
  const AppSyncListeners(this.ref);

  final WidgetRef ref;

  /// Registers every listener, in the same order as the original inline calls.
  void registerAll() {
    _pushRegistration();
    _presenceSync();
    _liveActivitySync();
    _widgetSync();
    _snapshotSync();
    _uploadDrain();
  }

  void _pushRegistration() {
    // Registers this device's FCM token once an active employee's or admin's
    // account doc resolves. Admins also get time-based nudges for jobs
    // they're assigned to. This is a no-op for signed-out users.
    ref.listen<AsyncValue<Map<String, dynamic>>>(currentUserDocProvider, (
      prev,
      next,
    ) {
      unawaited(ref.read(pushRegistrationControllerProvider).sync());
    });
  }

  void _presenceSync() {
    // Starts or stops the foreground location stream that feeds the travel-time
    // "leave now" reminders — same emission-driven shape as push registration above.
    ref.listen<AsyncValue<Map<String, dynamic>>>(currentUserDocProvider, (
      prev,
      next,
    ) {
      unawaited(ref.read(presenceSyncControllerProvider).sync());
    });
  }

  void _liveActivitySync() {
    // Registers this device's Live Activity APNs tokens so the server can show
    // the "time to leave" card on a locked phone. That only works on iOS 17.2+ —
    // other devices just get the plain leaveNow push.
    ref.listen<AsyncValue<Map<String, dynamic>>>(currentUserDocProvider, (
      prev,
      next,
    ) {
      unawaited(ref.read(liveActivityRegistrationControllerProvider).sync());
    });
  }

  /// True when an emission says nothing about whether the person is signed out.
  ///
  /// Both mirrors below publish `null` to mean SIGNED OUT and clear the App
  /// Group. But an `AsyncError` carries a null value too, and so does
  /// `AsyncLoading` — so keying on `value == null` alone made a failed Firestore
  /// read (past `retryAsync`) blank the home-screen widget and have Siri answer
  /// "no appointments" to someone who has jobs. Both surfaces are off-screen,
  /// so nothing reported it. A stale mirror beats a wrongly-empty one: keeping
  /// the last good payload is the honest degradation while the read is broken.
  static bool _isUnsettled(AsyncValue<Object?> next) =>
      next.isLoading || next.hasError;

  void _widgetSync() {
    // iOS home-screen widget only. It never wires up on Android, so the
    // employee-appointments listener it would open never opens.
    if (!Platform.isIOS) return;
    ref.listen<AsyncValue<Map<String, dynamic>?>>(widgetPayloadProvider, (
      prev,
      next,
    ) {
      if (_isUnsettled(next)) return;
      final payload = next.value;
      final service = ref.read(widgetSyncServiceProvider);
      if (payload == null) {
        unawaited(service.clear());
      } else {
        unawaited(service.sync(payload));
      }
    });
  }

  void _snapshotSync() {
    // iOS Siri App Intents extension only — same App Group, separate key.
    if (!Platform.isIOS) return;
    ref.listen<AsyncValue<Map<String, dynamic>?>>(scheduleSnapshotProvider, (
      prev,
      next,
    ) {
      if (_isUnsettled(next)) return;
      final payload = next.value;
      final service = ref.read(scheduleSnapshotServiceProvider);
      if (payload == null) {
        unawaited(service.clearSnapshot());
      } else {
        unawaited(service.writeSnapshot(payload));
      }
    });
  }

  void _uploadDrain() {
    // When we come back online after being offline, retry any queued photo
    // batches — once per flip.
    ref
      ..listen<bool>(isOfflineProvider, (previous, next) {
        final isSignedIn =
            ref.read(currentUserDocProvider).value?.isNotEmpty ?? false;
        if (previous == true && !next && isSignedIn) {
          unawaited(ref.read(appointmentImageUploadProvider).drainPending());
        }
      })
      // On startup or sign-in, drain once as soon as the account doc first
      // arrives. Storage rules require an authenticated user, so draining
      // while signed out would just re-queue everything.
      ..listen<AsyncValue<Map<String, dynamic>>>(currentUserDocProvider, (
        previous,
        next,
      ) {
        final wasEmpty = previous?.value?.isEmpty ?? true;
        final hasDoc = next.value?.isNotEmpty ?? false;
        if (wasEmpty && hasDoc) {
          unawaited(ref.read(appointmentImageUploadProvider).drainPending());
        }
      });
  }
}
