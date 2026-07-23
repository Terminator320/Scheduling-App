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

/// Cross-cutting sync wiring (device registration, mirrors, photo drain) extracted for testability; account-lifecycle listeners stay in main.dart due to registration order.
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
    // Starts/stops the background location stream feeding the travel-time "leave now" reminders, same emission-driven shape as push registration above.
    ref.listen<AsyncValue<Map<String, dynamic>>>(currentUserDocProvider, (
      prev,
      next,
    ) {
      unawaited(ref.read(presenceSyncControllerProvider).sync());
    });
  }

  void _liveActivitySync() {
    // Registers this device's Live Activity APNs tokens so the server can put the "time to leave" card on a locked phone (iOS 17.2+ only; other devices just get the plain leaveNow push).
    ref.listen<AsyncValue<Map<String, dynamic>>>(currentUserDocProvider, (
      prev,
      next,
    ) {
      unawaited(ref.read(liveActivityRegistrationControllerProvider).sync());
    });
  }

  void _widgetSync() {
    // iOS home-screen widget only — never wires on Android, so the employee-appointments listener it would open is never opened.
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
