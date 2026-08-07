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
    required this.openAppointment,
  });

  final AppLogger logger;

  /// The existing signed-in-only appointment opener, guards unchanged.
  final Future<void> Function(String appointmentId) openAppointment;

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
        case IgnoredLink():
          return;
      }
    } catch (e, st) {
      logger.warn('DEEP-LINK open failed', e, st);
    }
  }
}
