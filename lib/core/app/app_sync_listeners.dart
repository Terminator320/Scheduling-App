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

/// The app's cross-cutting, fire-and-forget sync wiring: device registration
/// (push, presence, Live Activity), the two off-screen schedule mirrors (iOS
/// home-screen widget, Siri snapshot), and the offline photo-upload drain.
///
/// Extracted from `_PaulAppState` so this wiring can be exercised without
/// building a `MaterialApp`. The account-lifecycle listeners (disabled /
/// role-revoked / deleted) deliberately stay in `main.dart`: they drive a
/// sign-out + navigation through shared state, and their registration ORDER
/// relative to each other is load-bearing.
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
    // Registers this device's FCM token when an active employee's or admin's
    // account doc resolves (admins get time-based nudges for jobs they're
    // assigned to); a no-op for signed-out users.
    ref.listen<AsyncValue<Map<String, dynamic>>>(currentUserDocProvider, (
      prev,
      next,
    ) {
      unawaited(ref.read(pushRegistrationControllerProvider).sync());
    });
  }

  void _presenceSync() {
    // Starts/stops the background location stream that feeds the travel-time
    // "leave now" reminders — active employees and admins (both receive the
    // timed pushes). Same emission-driven shape as push registration above.
    ref.listen<AsyncValue<Map<String, dynamic>>>(currentUserDocProvider, (
      prev,
      next,
    ) {
      unawaited(ref.read(presenceSyncControllerProvider).sync());
    });
  }

  void _liveActivitySync() {
    // Registers this device's Live Activity APNs tokens (push-to-start plus
    // one per live card) so the server can put the "time to leave" card on a
    // closed, locked phone. iOS 17.2+ only; every other device registers
    // nothing and just gets the plain `leaveNow` push.
    ref.listen<AsyncValue<Map<String, dynamic>>>(currentUserDocProvider, (
      prev,
      next,
    ) {
      unawaited(ref.read(liveActivityRegistrationControllerProvider).sync());
    });
  }

  void _widgetSync() {
    // iOS home-screen widget only. On Android (dev harness) this never wires,
    // so the employee-appointments listener it would open is never opened.
    if (!Platform.isIOS) return;
    ref.listen<AsyncValue<Map<String, dynamic>?>>(widgetPayloadProvider, (
      prev,
      next,
    ) {
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
    // Reconnect: retry queued photo batches once per offline→online flip.
    ref
      ..listen<bool>(isOfflineProvider, (previous, next) {
        final isSignedIn =
            ref.read(currentUserDocProvider).value?.isNotEmpty ?? false;
        if (previous == true && !next && isSignedIn) {
          unawaited(ref.read(appointmentImageUploadProvider).drainPending());
        }
      })
      // Startup / sign-in: one drain when the account doc first arrives
      // (Storage rules need an authed user; a signed-out drain re-queues).
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
