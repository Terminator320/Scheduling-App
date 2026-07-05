import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

import 'package:scheduling/l10n/l10n.dart';

/// Sanitized error categories safe to surface in UI text.
/// Raw Firebase codes and stack traces must never reach the UI (security.md);
/// full detail still goes to Crashlytics via the catch site's logger.warn.
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

/// "{intro} — {cause}. ({tag})". The tag must match the prefix of the
/// catch site's logger.warn label so user reports map to Crashlytics lines.
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
