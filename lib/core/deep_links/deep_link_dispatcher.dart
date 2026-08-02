import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import 'package:scheduling/core/deep_links/deep_link_target.dart';
import 'package:scheduling/core/logging/app_logger.dart';

/// The one `app_links` consumer. Classifies every inbound URL and hands the
/// work to the host's callbacks — it never reaches into the app state, which
/// is what lets its routing decisions be tested without the plugin.
class DeepLinkDispatcher {
  DeepLinkDispatcher({
    required this.logger,
    required this.isSignedIn,
    required this.openAppointment,
    required this.noticeSignOutToAcceptInvite,
    required this.awaitLoginRoute,
    required this.pushInviteCode,
  });

  final AppLogger logger;

  /// A live session sends the invite branch down the notice path — accepting
  /// an invite needs the NEW account's session.
  final bool Function() isSignedIn;

  /// The existing signed-in-only appointment opener, guards unchanged.
  final Future<void> Function(String appointmentId) openAppointment;

  /// Surfaces the "sign out first" info notice. Never signs anyone out — a URL
  /// any web page can launch must not be able to tear down a session.
  final Future<void> Function() noticeSignOutToAcceptInvite;

  /// Resolves true once `/login` is the navigator's top route.
  final Future<bool> Function() awaitLoginRoute;

  final void Function(String code) pushInviteCode;

  StreamSubscription<Uri>? _subscription;

  /// Subscribes to inbound links and drains the cold-start launch URL.
  void start() {
    unawaited(() async {
      try {
        final appLinks = AppLinks();
        _subscription = appLinks.uriLinkStream.listen(
          handleLink,
          onError: (Object e, StackTrace st) =>
              logger.warn('DEEP-LINK stream error', e, st),
        );
        final initial = await appLinks.getInitialLink();
        if (initial != null) await handleLink(initial);
      } catch (e, st) {
        logger.warn('DEEP-LINK setup failed', e, st);
      }
    }());
  }

  void dispose() {
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  /// Swallows its own errors so nothing escapes to the zone handler as a
  /// FATAL crash — same posture as the widget/push tap handlers.
  @visibleForTesting
  Future<void> handleLink(Uri uri) async {
    try {
      switch (classifyDeepLink(uri)) {
        case AppointmentLink(:final id):
          await openAppointment(id);
        case InviteLink(:final code):
          await _openInvite(code);
        case IgnoredLink():
          return;
      }
    } catch (e, st) {
      logger.warn('DEEP-LINK open failed', e, st);
    }
  }

  Future<void> _openInvite(String code) async {
    if (isSignedIn()) {
      await noticeSignOutToAcceptInvite();
      return;
    }
    // First-launch onboarding never reaches /login until the user finishes it,
    // so a timeout is expected rather than a defect: give up quietly — the
    // code still works via "Accept your invite" on the sign-in screen.
    if (!await awaitLoginRoute()) {
      logger.breadcrumb('DEEP-LINK invite gave up waiting for the login route');
      return;
    }
    pushInviteCode(code);
  }
}
