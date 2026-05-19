import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

import 'package:scheduling/l10n/l10n.dart';

/// Sanitized error categories safe to surface in UI text.
/// Raw Firebase codes and stack traces must never reach the UI (security.md);
/// full detail still goes to Crashlytics via the catch site's logger.warn.
enum ErrorCause { offline, permissionDenied, notFound, unknown }

ErrorCause classifyError(Object error) {
  if (error is FirebaseException) {
    return switch (error.code) {
      'unavailable' ||
      'network-request-failed' ||
      'deadline-exceeded' => ErrorCause.offline,
      'permission-denied' => ErrorCause.permissionDenied,
      'not-found' => ErrorCause.notFound,
      _ => ErrorCause.unknown,
    };
  }
  if (error is SocketException || error is TimeoutException) {
    return ErrorCause.offline;
  }
  return ErrorCause.unknown;
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
  final cause = switch (classifyError(error)) {
    ErrorCause.offline => l10n.error_causeOffline,
    ErrorCause.permissionDenied => l10n.error_causePermissionDenied,
    ErrorCause.notFound => l10n.error_causeNotFound,
    ErrorCause.unknown => l10n.error_causeUnknown,
  };
  return l10n.error_noticeWithCause(intro, cause, tag);
}
