import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/connectivity/connectivity_providers.dart';
import 'package:scheduling/core/notices/notice_service.dart';

import 'package:scheduling/l10n/l10n.dart';

/// Sanitized error categories safe to show in the UI — no Firebase codes or
/// stack traces leak through. Full detail still goes to Crashlytics.
enum _ErrorCause { offline, permissionDenied, notFound, unknown }

_ErrorCause _classifyError(Object error) {
  if (error is FirebaseException) {
    return switch (error.code) {
      'unavailable' ||
      'network-request-failed' ||
      'deadline-exceeded' => _ErrorCause.offline,
      'permission-denied' => _ErrorCause.permissionDenied,
      'not-found' => _ErrorCause.notFound,
      _ => _ErrorCause.unknown,
    };
  }
  if (error is SocketException || error is TimeoutException) {
    return _ErrorCause.offline;
  }
  return _ErrorCause.unknown;
}

/// Composes "{intro} — {cause}. ({tag})". The tag must match the catch
/// site's logger.warn prefix, so a user's bug report can be traced back to
/// the right Crashlytics line.
String composeErrorNotice(
  BuildContext context, {
  required String intro,
  required String tag,
  required Object error,
}) {
  final l10n = context.l10n;
  final cause = switch (_classifyError(error)) {
    _ErrorCause.offline => l10n.error_causeOffline,
    _ErrorCause.permissionDenied => l10n.error_causePermissionDenied,
    _ErrorCause.notFound => l10n.error_causeNotFound,
    _ErrorCause.unknown => l10n.error_causeUnknown,
  };
  return l10n.error_noticeWithCause(intro, cause, tag);
}

/// Fails a write fast when the device is offline, surfacing the standard
/// cause+tag notice. Returns true when it fired, so the caller returns.
///
/// An awaited Firestore write only resolves on server ack, so without this the
/// button spins until the connection returns. Every widget-layer write guard
/// goes through here: the block was copy-pasted at six call sites differing
/// only in [intro] and [tag], and [tag] MUST match the `logger.warn` prefix at
/// the same site or a user's screenshot can't be traced to its Crashlytics line.
///
/// The two invite-acceptance screens deliberately don't use this — they surface
/// offline through their own `AuthBanner`, not a notice.
bool guardedOffline(
  BuildContext context,
  WidgetRef ref, {
  required String intro,
  required String tag,
}) {
  if (!ref.read(isOfflineProvider)) return false;
  ref
      .read(noticeServiceProvider)
      .error(
        composeErrorNotice(
          context,
          intro: intro,
          tag: tag,
          error: const SocketException('offline'),
        ),
      );
  return true;
}
