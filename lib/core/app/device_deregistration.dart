import 'package:flutter_riverpod/flutter_riverpod.dart';

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
/// Typed on [WidgetRef] because all three exits are widget-layer: the two
/// Settings actions and `AccountExitListeners`, which holds one to drive its
/// `ref.listen`s.
Future<void> deregisterThisDevice(WidgetRef ref) async {
  await ref.read(pushRegistrationControllerProvider).unregisterCurrentDevice();
  await ref.read(presenceSyncControllerProvider).unregister();
  await ref.read(liveActivityRegistrationControllerProvider).unregister();
}
