import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/live_activity/application/live_activity_registration_controller.dart';
import 'package:scheduling/features/notifications/application/push_registration_controller.dart';
import 'package:scheduling/features/presence/application/presence_sync_controller.dart';

/// Drops every server-side registration this DEVICE holds, in the one order
/// that works.
///
/// Push token, then presence, then the Live Activity tokens — and all three
/// before whatever revokes the credential (`signOut`, `deleteAccount`, or the
/// server-side disable). Each needs an authenticated caller to reach its own
/// documents, so a teardown that revokes first leaves the rows behind: a stale
/// `fcmToken` keeps pushing to a signed-out device, and a stale
/// `presence/location` keeps rendering the person on the admin's live map.
///
/// There is exactly ONE owner because the order is load-bearing and there are
/// three exits that need it — the runtime account-deletion signal
/// (AccountExitListeners) and both of Settings' own paths (sign out,
/// delete account), which each had their own hand-written copy. Adding a fourth
/// token store previously meant three edits with no compile error to catch a
/// miss, and only one of the three was covered by a test.
///
/// Every step is best-effort by contract: callers run this ahead of the action
/// that actually protects the user, so a failure here must not block it. The
/// individual controllers already swallow and log their own failures.
///
/// **Each step is ISOLATED, so the contract holds between them as well as
/// around them.** They used to be three bare awaits, which meant a throw from
/// the first silently skipped the other two — and the ones it skipped are the
/// ones whose residue is visible to other people: a stale `presence/location`
/// keeps rendering the person on the admin's live map, and
/// `LiveMapAggregator.join` filters on missing/inactive user, never on
/// freshness, so that pin is indistinguishable from a live one. A leak that
/// only happens when something else already failed is exactly the kind nobody
/// reports.
///
/// The ORDER still matters and is unchanged; isolation only stops one failure
/// from cancelling the rest.
///
/// Typed on [WidgetRef] because all three exits are widget-layer: the two
/// Settings actions and `AccountExitListeners`, which holds one to drive its
/// `ref.listen`s.
Future<void> deregisterThisDevice(WidgetRef ref) async {
  // Resolved up front — the awaits below can outlive the caller's widget, and
  // `ref.read` throws on an unmounted consumer under Riverpod 3.
  final logger = ref.read(loggerProvider);
  final push = ref.read(pushRegistrationControllerProvider);
  final presence = ref.read(presenceSyncControllerProvider);
  final liveActivity = ref.read(liveActivityRegistrationControllerProvider);

  Future<void> step(String label, Future<void> Function() run) async {
    try {
      await run();
    } catch (e, st) {
      logger.warn('ACCOUNT-EXIT $label de-registration failed', e, st);
    }
  }

  await step('push', push.unregisterCurrentDevice);
  await step('presence', presence.unregister);
  await step('liveActivity', liveActivity.unregister);
}
