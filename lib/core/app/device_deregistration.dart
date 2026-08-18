import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/images/appointment_image_loader.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/live_activity/application/live_activity_registration_controller.dart';
import 'package:scheduling/features/notifications/application/push_registration_controller.dart';
import 'package:scheduling/features/presence/application/presence_sync_controller.dart';

class DeviceDeregistrationDeps {
  DeviceDeregistrationDeps({
    required this.logger,
    required this.push,
    required this.presence,
    required this.liveActivity,
    required this.imageLoader,
  });

  factory DeviceDeregistrationDeps.fromRef(Ref ref) => DeviceDeregistrationDeps(
    logger: ref.read(loggerProvider),
    push: ref.read(pushRegistrationControllerProvider),
    presence: ref.read(presenceSyncControllerProvider),
    liveActivity: ref.read(liveActivityRegistrationControllerProvider),
    imageLoader: ref.read(appointmentImageLoaderProvider),
  );

  factory DeviceDeregistrationDeps.fromWidgetRef(WidgetRef ref) =>
      DeviceDeregistrationDeps(
        logger: ref.read(loggerProvider),
        push: ref.read(pushRegistrationControllerProvider),
        presence: ref.read(presenceSyncControllerProvider),
        liveActivity: ref.read(liveActivityRegistrationControllerProvider),
        imageLoader: ref.read(appointmentImageLoaderProvider),
      );

  final AppLogger logger;
  final PushRegistrationController push;
  final PresenceSyncController presence;
  final LiveActivityRegistrationController liveActivity;
  final AppointmentImageLoader imageLoader;
}

/// Drops every server-side registration this DEVICE holds, in the one order
/// that works — and then forgets the session's local photo cache.
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
/// Typed on explicit dependencies so widget callers and long-lived controllers
/// can share the same teardown path without generic `read` indirection.
Future<void> deregisterThisDevice(DeviceDeregistrationDeps deps) async {
  final logger = deps.logger;
  final push = deps.push;
  final presence = deps.presence;
  final liveActivity = deps.liveActivity;
  // Hoisted for the same reason, even though it is USED last: the read is
  // what throws, not the call. Left at the bottom it sat after three network
  // round-trips and outside `step`'s catch, so on the account-deleted path —
  // where the tree is being torn down during exactly those awaits — it threw
  // out of this function and `AccountExitListeners` never reached `signOut()`,
  // leaving a deleted account signed in and the cache it exists to clear
  // uncleared.
  final imageLoader = deps.imageLoader;

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

  // LOCAL, and deliberately last: nothing above depends on it.
  // `appointmentImageLoaderProvider` is a plain `Provider`, so its byte cache
  // lives for the whole process — up to 24 MB of this user's job photos would
  // otherwise stay resident in the heap across sign-out and into the next
  // user's session on a shared device — and its DISK half outlives the process
  // entirely, which is what makes this a leak rather than a memory-forensics
  // footnote. It is not a rules bypass (serving them still needs the next
  // reader to be entitled to the same `storagePath`), which is why it sits
  // here rather than above the credential-dependent steps — but this is the
  // single owner of "forget this session", and it was the one thing it did not
  // forget. It goes through `step` like the rest now that it touches the file
  // system and can therefore fail.
  await step('imageCache', imageLoader.clear);
}
